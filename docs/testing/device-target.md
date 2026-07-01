# Device-Target Test Execution

The pvtest suite (see [automated-workflow.md](automated-workflow.md)) runs the *same* tests
against three kinds of target without a separate suite:

- a single **appengine** container (the classic local/CI path),
- a **slot pool** of up to `-p` appengine containers driven in parallel,
- a **real device** over the network (future automated flashing).

This is achieved by splitting the old single `pantavisor-appengine-tester` container into a thin
**`pantavisor-tester`** (the runner: `pvtest-run`, `pvr`, `jq`, `curl`, `valgrind`) and one or more
device-like **`pantavisor-appengine`** containers that expose SSH + the pvr HTTP API exactly as a real
device would. The tester drives each target over two channels:

- **`PVTEST_EXEC`** — a command prefix (typically `ssh …`) used to run `pvcontrol`/`pventer` on the
  target. The `pvcontrol()`/`pventer()`/`pvcurl()` wrappers in `pvtest/utils` route through it; when
  unset, commands run locally (legacy single-device behaviour is unchanged).
- **`PVTEST_HOST`** — the host for the target's pvr HTTP endpoint (`http://$PVTEST_HOST:12368/cgi-bin/pvr`),
  used by `pvr`/`curl` to deploy revisions.

Both variables are set automatically by the runner (per slot, rebuilt each time a slot re-types); they
are never set by the user. `test.docker.sh … -p N` runs the slot pool: a single tester owns `N` slots
and asks the host to boot/re-type each slot's container on demand over a control channel. (The
`PVTEST_APPENGINES` env names a single pre-booted container and is used only by interactive/manual
mode.)

---

## Topology

**Tester + appengine pool**
```
 HOST
 ┌────────────────────────────────────────────────────────────────────────┐
 │  test.docker.sh   (slot pool: -p N slots, host re-types on demand)      │
 │                                                                         │
 │  ┌────────────────────┐        ┌──────────────────────────┐            │
 │  │  pantavisor-tester │──SSH───►│  pantavisor-appengine-0  │            │
 │  │                    │ (EXEC) │  ├─ pantavisor (PID1)     │            │
 │  │  pvtest-run        │──HTTP──►│  ├─ pvr-sdk (LXC)        │            │
 │  │  pvr  curl  jq     │ :12368 │  ├─ pvcontrol / pventer   │            │
 │  │  valgrind          │ (HOST) │  └─ sshd                  │            │
 │  │                    │         └──────────────────────────┘            │
 │  │  N slots over a    │──SSH───►┌──────────────────────────┐            │
 │  │  global FIFO; each │──HTTP──►│  pantavisor-appengine-N  │  …         │
 │  │  slot re-types its │         └──────────────────────────┘            │
 │  │  container on demand│                                                │
 │  └────────────────────┘                                                 │
 └────────────────────────────────────────────────────────────────────────┘
```

**Tester + real device** *(runner integration is future work — see PR TODO)*
```
 HOST
 ┌────────────────────────────────────────────────────────────────────────┐
 │  test.docker.sh   PVTEST_EXEC="ssh …"  PVTEST_HOST=<device-ip>          │
 │                                                                         │
 │  ┌────────────────────┐        ┌──────────────────────────┐            │
 │  │  pantavisor-tester │──SSH───►│   arm32 / arm64 device   │            │
 │  │                    │ (EXEC) │  ├─ pantavisor (init/PID1)│            │
 │  │  pvtest-run        │──HTTP──►│  ├─ pvr-sdk (LXC)        │            │
 │  │  pvr  curl  jq     │ :12368 │  ├─ pvcontrol / pventer   │            │
 │  └────────────────────┘ (HOST) │  └─ sshd                  │            │
 │                                 └──────────────────────────┘            │
 └────────────────────────────────────────────────────────────────────────┘
```

Each `test.json` may carry a `"devices"` array. Absent/empty means "run everywhere" (the default for
all tests). When a test is incompatible with a target, its `"devices"` field restricts it; the runner
sets `PVTEST_DEVICE` and skips tests that exclude that target.

---

## Execution flow

```
 ┌────────────────────────────┐
 │  Init device(s)  (once)    │   per appengine, in parallel:
 │  • wait pv-ctrl + DONE     │   • collect device info
 │                            │
 └─────────────┬──────────────┘
               │ pool ready
               ▼
 ┌────────────────────────────┐
 │  Install initial revision  │◄─────────────────────────────┐
 │  (setup_test)              │                               │
 │  • pvr init                │                               │
 │  • pvr merge each tarball  │                               │ more tests
 │  • pvr checkout && commit  │                               │ (no reset
 │  • pvr post --rev <test>   │                               │  between
 │  • wait DONE|UPDATED+READY │                               │  tests)
 └─────────────┬──────────────┘                               │
               │ device live on the test's revision           │
               ▼                                              │
 ┌────────────────────────────┐                               │
 │  Run test  (exec_test)     │───────────────────────────────┘
 │  • run resources/test      │
 │  • diff vs golden output   │
 └─────────────┬──────────────┘
               │ all tests done
               ▼
 ┌────────────────────────────┐
 │  Teardown  (once)          │   per appengine:
 │  • poweroff                │   • lenient pantavisor shutdown
 └────────────────────────────┘
```

The diagram shows one slot's lifecycle. The slot pool runs `-p` of these in
parallel over one global queue: a slot boots its container, inits it, claims it if
the runner-type needs it, then runs the same-type tests back-to-back (install +
run per test). When the next pending test needs a different `required-config`, the
slot **re-types** — detach (delete the claim if any), ask the host to stop the old
container and boot a new one with the new `PV_*` env, then init again. So *init* and
*teardown* happen once per container, which for a slot that re-types means several
times across a run, not once per slot.

### Init device (once per container)

`init_device` waits for pv-ctrl to answer and the current revision to reach `DONE`, then collects device
info (`pvcontrol devmeta ls`). It runs each time a slot boots or re-types a container; a container that
fails init aborts the tests stranded on that slot.

### Install initial revision (before each test)

Each test's starting state is built **solely from the tarballs declared in its `test.json`** — there is
no per-test reset. Every tarball is a self-contained pvr *fragment* (a `json` state file + `objects/`);
`bsp.tgz` + `pvr-sdk.tgz` + the app tarball(s) together form a complete revision. `setup_test`:

1. `pvr init` an empty repo,
2. `pvr merge` each extracted fragment,
3. `pvr checkout && pvr commit` (checkout materialises the merged files so the commit captures the full
   revision),
4. `pvr post --rev locals/<test_id> http://$PVTEST_HOST:12368/cgi-bin/pvr`,
5. `wait_for_new_revision` — pv-ctrl responsive, the posted revision current with a terminal-good step
   status (`DONE` or `UPDATED`), and `pantavisor.status` `READY`.

Because each revision is self-contained, tests never inherit each other's state, so the previous
per-test "reset to factory" step is gone. `setup_test` only *provisions*; the test body runs afterward
in `exec_test`.

### Run test

`exec_test` runs the test's `resources/test` script (with `pvtest/utils` sourced so `pvcontrol`/`pventer`
route via `PVTEST_EXEC`), captures stdout, and `eval_test` diffs it against the golden `output` file.
In slot-pool mode, per-slot appengine logs are interleaved into the per-test `test.log`.

### Teardown (on re-type and at end of run)

A slot powers off and discards its container when it re-types to a new runner-type, and any still-running
slot containers get a lenient `poweroff` at the end of the run. The framework does **not** roll the
device back to factory between or after tests — each test fully defines its own starting state by posting
its initial revision (see above). When running from the interactive tester console, shutdown happens on
console exit.

---

## Waiting for a posted revision

After `setup_test` posts a revision it must wait for it to fully apply before continuing to drive the
device. `wait_for_new_revision <rev> [require_ready]` (in `pvtest/utils`) centralises this:

1. pv-ctrl is responsive (`pvcontrol devmeta ls`),
2. the target revision is current,
3. its step status is terminal-good — `DONE` (a factory/boot revision) or `UPDATED` (a freshly applied
   local revision); both mean the revision is live and ready to test (`ERROR`/`WONTGO` fail fast),
4. if `require_ready` is `true` (default), `pantavisor.status` is `READY`.

Pass `require_ready=false` for BSP-only revisions that never bring up containers and so never reach
`READY`.

## Logging

Every external call the runner makes — `pvcontrol`, `pvr`, and target-side `curl` — is preceded by a
`pvtest_log` line (`DEBUG` for routine steps, `INFO` for milestones) so a run log shows exactly what was
executed against the device and when. `pvcontrol cmd …` calls (e.g. `poweroff`) go through the
`pv_ctrl` wrapper, which logs and retries on transient `503` (command-slot busy) responses. This
convention applies to the runner orchestration only — not to the individual `resources/test` scripts,
whose stdout is diffed against golden output.
