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

**Tester + real device**
```
 HOST
 ┌────────────────────────────────────────────────────────────────────────┐
 │  test.docker.sh   --devices devices.txt   PVTEST_DEVICE=m2              │
 │                                                                         │
 │  ┌────────────────────┐        ┌──────────────────────────┐            │
 │  │  pantavisor-tester │──SSH───►│   arm32 / arm64 device   │            │
 │  │   (x86_64, runs on │ (EXEC) │  ├─ pantavisor (init/PID1)│            │
 │  │    host/CI runner) │──HTTP──►│  ├─ pvr-sdk (LXC)        │            │
 │  │  pvtest-run        │ :12368 │  ├─ pvcontrol / pventer   │            │
 │  │  pvr  curl  jq     │ (HOST) │  └─ sshd                  │            │
 │  └────────────────────┘         └──────────────────────────┘            │
 │           │  device console (tty, read directly on the host,           │
 │           │  same convention as `docker logs -f` for an appengine)      │
 │           ▼                                                            │
 │  appengine-<name>.log                                                  │
 └────────────────────────────────────────────────────────────────────────┘
```

Each `test.json` may carry a `"devices"` array. Absent/empty means "run everywhere" (the default for
all tests). When a test is incompatible with a target, its `"devices"` field restricts it; the runner
sets `PVTEST_DEVICE` and skips tests that exclude that target.

### Real-device mode (`--devices`)

`test.docker.sh run ... --devices FILE` replaces the Docker appengine pool with a **single** real
hardware target. It is mutually exclusive with `-p>1`/`-m`/`-n`/`-V`; `-i` **is** supported (it opens
the tester console wired to the device — see below). This is a deliberate downgrade from an earlier
multi-device pool: the manifest keeps the same format but must contain exactly one device (more than
one is a hard error), and there is no pool/dispatcher — one tester runs every selected test against the
one device sequentially. `FILE` is a blank-line-separated list of `key=value` stanzas (only one is
allowed):

```
name=m2-01
ip=192.168.1.50
exec=ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /keys/m2.pem root@192.168.1.50
tty=/dev/serial/by-id/usb-FTDI_FT232R-if00-port0
baud=115200
```

`name` (slot binding + log filename), `ip` (→ `PVTEST_HOST`), `exec` (→ `PVTEST_EXEC`), `tty`
(host-local serial device path, read directly the same way `_boot_appengine` backgrounds `docker logs
-f`), `baud` (optional, default 115200). Prefer `/dev/serial/by-id/...` stable symlinks over raw
`/dev/ttyUSBN` paths, since USB enumeration order isn't guaranteed across host reboots.

A real device can't be re-typed/rebooted with new config the way a Docker appengine container can, so
device mode uses a **single-device runner** (`run_single_device` in `pvtest-run.in`, separate from the
appengine `run_slot_pool`/`slot_worker`): the one device binds once, inits once, then every selected
test runs against it sequentially through `run_test_attempt` — no pool, no runner-type/claim-batching,
no re-type. Claims (`setup.self-claim`) are handled per-test via `handle_self_claim()`, the same call
the legacy single-device path already uses. At the end of the run, device mode releases the tty capture
and the device lock but does **not** power off the device by default — unlike a disposable container, a
real board should stay reachable after CI.

**Interactive (`-i`) against a device.** `test.docker.sh run <test> -i --devices FILE` boots nothing and
drops you into the tester console with `PVTEST_EXEC`/`PVTEST_HOST` pointing at the device, so
`pvcontrol`, `pventer` and `pvr` in that shell act on the real board. (No `PVTEST_QUEUE` is passed, so
`pvtest-run` runs `exec_interactive` instead of the test loop.)

Device console/tty logs reuse the `appengine-<name>.log` naming convention (keyed by the manifest's
`name=` instead of a container name), so `run_test_attempt`'s per-test log interleaving needs no
device-specific branching — the tester reads `$APPENGINE_LOGS/appengine-<name>.log` (a host directory
mounted read-only into the tester at `/work/hostlogs`) exactly the same way for a device or a
container.

**`required-config` vs. live-device matching (implemented).** A device's config can't be injected the
way an appengine container's is at boot, so `run_test_attempt` now matches each test's declared
`setup.required-config` against the device's actual `conf ls` (captured once by `init_device`) and
**SKIPs** the test on mismatch. It's gated on `PVTEST_MATCH_REQCFG` (set only by device mode) so the
appengine slot pool — which *does* inject required-config — never skips on it. See `_reqcfg_satisfied`
in `pvtest-run.in`.

**Still manual/future work, not solved by this iteration:**

- **Populating `"devices"` arrays.** Every existing `test.json` currently ships `"devices": []`
  (unrestricted). A real-device run will attempt every test whose `required-config` the device happens
  to satisfy unless someone first audits the suite and tags appengine-only tests (e.g. ones relying on
  injected `PV_DEBUG_SSH`, valgrind, or loop-device internals that don't apply to a real board).
- **Automated flashing.** Device mode assumes the device is already running whatever Pantavisor config
  it currently has; there is no flashing/provisioning step.

Because of the `"devices"` gap above, run device-mode suites **without** `--fail-on-skip` — SKIPPED
results are still expected until the suite has been triaged for hardware safety.

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
