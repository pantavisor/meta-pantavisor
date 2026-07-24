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
  A device manifest's `exec=ssh …` must include
  `-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2`:
  reboot-class updates black-hole established TCP connections, and an ssh without keepalives blocks
  on them forever. As a backstop, `_pv_exec` wall-bounds every forwarded call tester-side with
  `timeout` (`PVTEST_EXEC_TIMEOUT`, default 60 s; 600 s for `pvtx` tarball streaming).
- **`PVTEST_HOST`** — the host for the target's pvr HTTP endpoint (`http://$PVTEST_HOST:12368/cgi-bin/pvr`),
  used by `pvr`/`curl` to deploy revisions.

Both variables are set automatically by the runner (per slot, rebuilt each time a slot re-types); they
are never set by the user. `test.docker.sh … -p N` runs the slot pool: a single tester owns `N` slots
and asks the host to boot/re-type each slot's container on demand over a control channel. (The
`PVTEST_APPENGINES` env names a single pre-booted container and is used only by interactive/manual
mode.)

`--model` selects the **assignment model** for a run: **persistent** (the default) boots every test
under exactly its `config.env` — each of the `-p` workers keeps ONE persistent storage for the whole
pass and re-boots with new config only when a test actually needs it (merged into that test's own
setup power cycle — see Execution flow); **volatile** boots one fresh appengine container per test
(own storage, no re-typing), `-p` capping how many run concurrently — incompatible with `--devices`
and `-n`. Under persistent, each test starts from its own fresh child of the factory revision
installed by `setup_test`, followed by a synchronous gc. Volatile discards and re-boots a fresh
container per test instead, and — since that container is thrown away anyway — the test's
revision is seeded into `pv-appengine`'s first-boot pvtx (the image's `pvtx.d` plus the test's
tarballs mounted at `pvtx.extra.d`) and deployed under the same `locals/<id>` name, so the
container boots into it already committed. Pantavisor only auto-commits the revision it boots into
when that revision is literally named `0`, so `pv-appengine` also writes the `.pv/done` and
`.pv/progress` markers that path would have written — without them the revision comes up with no
progress at all and never reaches `DONE`. That is what makes the model cheap: no install and no
commit reboot, one pantavisor boot per test rather than three. No factory revision is deployed in
that case — it would never be booted or cloned, and the first gc reclaims it anyway — so a
volatile test starts against a trail holding exactly its own revision, where a persistent one
starts against a trail that has accumulated the worker's earlier tests. Against a real device
(`--devices`), persistent is the only usable model
(volatile needs a docker container per test). If the manifest's device sets `hook=` (a host command
that sets the device's boot env and power-cycles it, `config=` naming that command's config file), a
config mismatch re-types the device through the hook the same way a pool worker re-types a
container; without `hook=`, tests whose `config.env` the live device doesn't already satisfy are
SKIPPED instead. Want results from both models? Run `test.docker.sh` twice, once per `--model`.

---

## Topology

The tester is **always x86 and always runs on the host/CI runner** in both modes.
What changes is the target: an appengine pool runs *on the same host* (also x86),
whereas a real device is *external* and may be another architecture.

**Tester + appengine pool** — tester and appengines both on the HOST, all x86
```
 HOST (x86)
 ┌────────────────────────────────────────────────────────────────────────┐
 │  test.docker.sh   (slot pool: -p N slots, host re-types on demand)      │
 │                                                                         │
 │  ┌────────────────────┐        ┌──────────────────────────┐            │
 │  │  pantavisor-tester │──SSH───►│  pantavisor-appengine-0  │            │
 │  │   (x86, runner)    │ (EXEC) │  ├─ pantavisor (PID1)     │            │
 │  │  pvtest-run        │──HTTP──►│  ├─ pvr-sdk (LXC)        │            │
 │  │  pvr  curl  jq     │ :12368 │  ├─ pvcontrol / pventer   │            │
 │  │  valgrind          │ (HOST) │  └─ sshd                  │            │
 │  │                    │         └────────────┬─────────────┘            │
 │  │  N slots over a    │──SSH───►┌────────────┴─────────────┐            │
 │  │  global FIFO; each │──HTTP──►│  pantavisor-appengine-N  │  …         │
 │  │  slot re-types its │         └────────────┬─────────────┘            │
 │  │  container on demand│                     │ docker logs -f           │
 │  └────────────────────┘                      ▼                         │
 │                                       <container>.log  (on the host)    │
 └────────────────────────────────────────────────────────────────────────┘
```

**Tester + real device** — tester on the HOST (x86); the device is external and may be another arch
```
 HOST (x86 runner)                     external device (arm32/arm64, elsewhere)
 ┌────────────────────────────┐        ┌──────────────────────────┐
 │  test.docker.sh --devices  │        │   arm32 / arm64 device   │
 │                            │  SSH    │  ├─ pantavisor (init/PID1)│
 │  ┌────────────────────┐    │ (EXEC)  │  ├─ pvr-sdk (LXC)        │
 │  │  pantavisor-tester │────┼────────►│  ├─ pvcontrol / pventer  │
 │  │   (x86, runner)    │────┼──HTTP──►│  └─ sshd                  │
 │  │  pvtest-run        │    │ :12368  └────────────┬─────────────┘
 │  │  pvr  curl  jq     │    │                      │ serial (tty)
 │  └─────────┬──────────┘    │◄─────────────────────┘
 │            ▼               │
 │      <name>.log            │
 └────────────────────────────┘
```

The device console arrives over its serial `tty` (read directly on the host, the
same convention `docker logs -f` uses for an appengine) and is captured to
`<name>.log`.

Each `test.json` may carry a `"devices"` array — an allow-list of the target *classes* the
test is restricted to. Absent/empty means "run everywhere", the default for almost every test.
Use it for tests that *cannot* pass elsewhere: ones whose golden output asserts the appengine
baseline, or that need a pantavisor build feature a given BSP doesn't ship.

An entry matches `PVTEST_DEVICE_TYPE`: `appengine` for a container, the manifest's `type=` for
a real device. The class, not the runner — a pin holds for every board of that kind, so a
second board of the same model needs no test change. `PVTEST_DEVICE_NAME` identifies the
individual runner (container name, or the manifest's `name=`) and is never matched here.

```
"devices": ["appengine"]        # container only — e.g. asserts the appengine baseline
"devices": ["appengine", "<machine>"]   # also on every board of that machine class
```

See the bundled `README.md` and `devices.txt` for the `--devices` manifest format and how to
run against a real device. A manifest entry's `hook=`/`config=` fields (if set) let a config
mismatch re-type the device via that hook, the same way a pool worker re-types a container.
Without `hook=`, tests the live device doesn't already satisfy are SKIPPED instead — run
device-mode suites **without** `--fail-on-skip` until each test's `"devices"` array is triaged.

A hook is invoked as `hook [-c <config=>] KEY=VALUE ...`, and typically writes the boot env
as a full replacement — so passing only a test's own `config.env` would drop everything else
the device needs to stay usable. The manifest entry's optional `env=` field carries those
board-level tokens (space-separated `KEY=VALUE`, empty by default). The tester passes them
**ahead** of the test's own on every re-type, so the test still wins on any key both set, and
a board that boots with, say, a fixed log or secure-boot setting keeps it across re-types.
Leave `env=` empty for a hook that merges rather than replaces.

## Expected outcomes on real devices

Not every non-PASS is a bug. Triage device results against these classes first:

- **SKIPPED because the test is pinned to another target is the design.** A test whose
  `"devices"` allow-list excludes this target never runs here; the log line names the
  target and the list. Today that is `local/core/*-config-overload` (their golden output
  asserts appengine-specific config values, and `PV_POLICY=test` requires a `test.config`
  policy a BSP need not ship — a missing policy file is fatal to pantavisor init),
  `local/xconnect/*` (they need the `xconnect-dbus-systembus` build feature and its
  example containers, which a BSP without that feature does not build), and
  `local/services/daemons` (it asserts the appengine image's daemon set, which follows
  from that image's `PANTAVISOR_FEATURES` and differs on any real BSP).
- **SKIPPED on unmet `config.env`, when no `hook=` is configured, is the design, not a
  failure.** Without a hook, a real device's config is immutable per test, so e.g. the
  config-overload tests (`PV_POLICY=test`), the secureboot tests (`PV_SECUREBOOT_MODE=strict`)
  and `on-demand-gc` (`PV_STORAGE_LOGTEMPSIZE=` — persistent logs; a device that keeps logs on
  tmpfs legitimately loses them across its real reboots, independent of any hook) skip wherever
  the device's live config says otherwise. Never change a device's config/BSP just to un-skip a
  test — configure a `hook=` instead if the device supports boot-time config injection.
- **FAILED can be expected when the device BSP ships an older/foreign pantavisor** than the
  tests were authored against: CLI output skew (e.g. an old `pvcontrol` printing HTTP response
  headers) or a different built-in daemon set (e.g. no `pv-xconnect`) fail the diff and that is
  acceptable — the golden outputs track the pantavisor under test, not every BSP in the field.
- **Timeouts**: device runs default `PVTEST_TEST_TIMEOUT` to 1800 s (vs 600 s for containers) —
  updates may need real reboots (reboot-on-update policies) and every forwarded poll pays an
  ssh round-trip.

### Authoring for cross-target portability

- The test script runs in the **tester**; `pvcontrol`/`pvcurl`/`pventer` execute **on the
  device**. A file argument must exist where the tool runs: stage tester files with
  `pv_stage_file` (and clean up with `pv_unstage_file`), bring device-side output files back
  with `pv_fetch_file`.
- Don't lean on the device rootfs toolset: a BSP's busybox can be trimmed (no `sha256sum`, no
  `cut`). Create and hash payloads in the tester, which always has the full toolset.
- An old BSP's lxc (3.x) mounts container rootfs overlays **read-only** (newer lxc mounts them
  rw, which is why appengine differs). A container whose payload writes to `/tmp` (e.g.
  in-container `pvcontrol`/`pvcurl`) must mount its own tmpfs there via the `PV_LXC_EXTRA_CONF`
  template arg — see `pv-example-mgmt.args.json`.
- Observations of the **device baseline** (container set, bsp object names, storage mount
  prefix, log line format) are target-dependent — assert invariants or booleans about them,
  never a literal listing (see `local/security/object-checksum`), or filter to content the
  test itself installs (see `local/security/container-roles`).

---

## Execution flow

```
 ┌────────────────────────────┐
 │  Init device(s)  (once)    │   per appengine, in parallel:
 │  • readiness fence         │   • collect device info
 │    (SSH..pvr endpoint)     │   • clone + export factory revision
 └─────────────┬──────────────┘
               │ pool ready
               ▼
 ┌────────────────────────────┐
 │  Install initial revision  │◄─────────────────────────────┐
 │  (setup_test)              │                               │
 │  • install locals/<test>   │                               │
 │    (pvtx; pvr fallback)    │                               │ more tests
 │  • ONE power cycle:        │                               │
 │    re-type (config change) │                               │
 │    or reboot (commit)      │                               │
 │  • gc, unclaim, go-remote  │                               │
 │  • claim state, usrmeta    │                               │
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
 │  • unclaim/delete + poweroff│  • lenient pantavisor shutdown
 └────────────────────────────┘
```

The diagram shows one slot's lifecycle. The slot pool runs `-p` of these in
parallel over one global, pre-sorted queue (claim-needing tests first, equal
configs adjacent): a worker boots its slot's container with its first test's
config and inits it once; from there `setup_test` owns everything per test,
including the config change. When a test needs a different `config.env`,
`setup_test` itself powers the container off and asks the host to boot a new
generation with the new `PV_*` env **on the same storage** — the new instance
boots straight into the pending test revision, so the config change and the
commit reboot cost a single power cycle. Claim state is also settled per test
at the end of `setup_test`; a claim persists on the worker's storage across
adjacent claim tests (state-driven no-ops) and is deleted at worker detach.

### Init device (once per attach)

`init_device` runs the [readiness fence](#waiting-for-a-target-to-come-up), collects device info
(`pvcontrol devmeta ls`), and clones + exports the factory revision the tests build on. It runs
when a worker first boots its slot's container (mid-setup re-types keep the factory artifacts,
re-keyed to the new container name); a container that fails init aborts the tests stranded on
that slot.

A mid-setup re-type is the same event — the host discards the container and boots a new generation
on the same storage — so it runs the same fence, only keyed on the pending test revision reaching
`DONE` instead of the current one. Skipping any of its stages there is what used to make the first
`pvr clone` of the following test race the freshly booted pvr endpoint.

### Install initial revision (before each test)

Each test's starting state is the device's **factory revision plus the tarballs declared in its
`test.json`**, installed by `setup_test` as the deterministically named revision `locals/<test_id>`
— a fresh child of the pristine factory clone, so tests never inherit each other's state even on a
storage that persists for the whole pass (a missing factory clone aborts the test). Every tarball
is a self-contained pvr *fragment* (a `json` state file + `objects/`); the factory export + the app
tarball(s) together form a complete revision. `setup_test`:

1. waits for the device to settle from the previous test — `wait_for_current_settled`, which
   drains to a terminal step status and then waits for `READY` and the pvr endpoint, so the
   install below cannot race the pvr endpoint,
2. installs the revision with `pvtx` (begin empty, add factory export + tarballs, commit, run),
   falling back to a tester-side seeded-from-factory `pvr post --rev locals/<test_id>` when the
   device rootfs lacks `pvtx`,
3. `wait_for_target_ready` — the posted revision current with a terminal-good step status
   (`DONE` or `UPDATED`), then `READY` and the pvr endpoint,
4. takes at most ONE power cycle: a config mismatch re-types the container on the same storage
   (persistent pool; the new generation boots the pending revision and commits it), otherwise a
   still-pending (`UPDATED`) revision is committed with a plain reboot — then waits for `DONE`,
5. runs the synchronous garbage collector (`pvcontrol storage gc`) so the previous test's
   `locals/*` revisions are reclaimed; a `self-claim: "false"` test whose device is still claimed
   from a previous test is unclaimed **now, before go-remote** — with the Hub client down, a stale
   in-flight trail update cannot resume, so it can neither reject the unclaim (503 "update
   ongoing") nor apply over the just-installed revision — and then goes remote (a `locals/*`
   current revision otherwise drops the device to local mode; skipped when the config guarantees
   a rejection: `PV_CONTROL_REMOTE=0`, or already remote via `PV_CONTROL_REMOTE_ALWAYS=1`),
6. settles the claim state the test wants (`setup.self-claim`, `handle_self_claim`) — after
   go-remote so the Hub client is up, and on a committed `DONE` revision so an unclaimed device can
   walk register→claim; a device unclaimed in step 5 has its old Hub identity deleted here, once
   it is claimable again — and finally applies the test's usrmeta (local + Hub-side, which needs
   the claim already in place).

`setup_test` only *provisions*; the test body runs afterward in `exec_test`.

### Run test

`exec_test` runs the test's `resources/test` script (with `pvtest/utils` sourced so `pvcontrol`/`pventer`
route via `PVTEST_EXEC`), captures stdout, and `eval_test` diffs it against the golden `output` file.
In slot-pool mode, per-slot appengine logs are interleaved into the per-test `test.log`.

### Teardown (per test, and at worker detach)

Per test, `teardown_test` removes the applied usrmeta (local + Hub) and, in the volatile model
only, deletes the test's self-claimed device (the container dies with the test). In the persistent
pool a claim survives re-types (it lives on the worker's storage) and is settled per test by
`handle_self_claim`; the worker's **final detach** cleans up for real: a device that can still walk
back to claimable is **unclaimed** first — after waiting for any in-flight update to settle
(pv rejects unclaim with 503 while one is ongoing), `pvcontrol cmd unclaim` strips the creds from
config/pantahub.config (reboot-free — the device walks idle→register→claim on its own), the worker
waits for `pantahub.state=claim`, and only then deletes the device from the Hub, so a failed
unclaim never leaves the device Hub-deleted while still claimed on-device; otherwise it is deleted
from the Hub directly. Then the container gets a lenient `poweroff`. The container is discarded but
its storage lineage (`storage/<tag>/<key>/`) survives re-types within the pass. When running from
the interactive tester console, shutdown happens on console exit.

---

## Waiting for a target to come up

Every moment a target comes (back) up — first init, a pool re-type, a device hook re-type, a reboot,
a crash — goes through one fence, `wait_for_target_ready [label] [rev] [status] [ready] [pvr]`
(in `pvtest/utils`). Its stages are waited in order and logged as they are reached, so a timeout
names the stage that hung instead of reporting a generic "device not ready":

1. **SSH** reachable (skipped when there is no `PVTEST_EXEC`), failing fast on a permanent auth
   error rather than polling the full timeout — this is what tells "the board/container is not up"
   apart from "pv-ctrl is not up",
2. **pv-ctrl** responsive (`pvcontrol devmeta ls`),
3. `rev` is the **current revision** (skipped when empty: whatever is current),
4. its **step status** is in the accepted set — `DONE` (a committed revision), `UPDATED` (a freshly
   applied local revision), or `DONE|UPDATED` for either; `ERROR`/`WONTGO` fail fast unless asked for,
5. `pantavisor.status` is **`READY`**,
6. the **pvr HTTP endpoint** on `:12368` answers — served by a *container*, so it comes up
   after `READY`. Which container provides it is target-specific and deliberately not
   checked: only the endpoint has to be there.

Stages 5 and 6 are not optional. "Ready" means the target can be driven, and everything that drives
one talks pv-ctrl and pvr; a target that never brings its containers up is not ready to be tested,
and continuing anyway only moves the failure somewhere less obvious. Because the fence guarantees
both, no caller has to fence either itself — the runner has no standalone readiness or endpoint
polls left.

The fence always logs every stage, at `INFO`, with `ERROR` on the stage that failed — there is no
quiet mode, because there is no case where a stuck target is better diagnosed by saying nothing.
`label` is only a context prefix (`init`, `after crash 2`, …); pass one whenever a run fences more
than once, or the stage lines are identical and the log cannot say which fence stalled.

Where those lines go is decided by `pvtest_log` from *context*, not from severity: `exec_test` sets
`PVTEST_LOG_STDERR=1` in the script it generates, and inside a test script stdout is not a log
channel at all — it is the data diffed against `output` — so every level goes to stderr there, which
`test.log` captures just the same (and which the diff display shows next to a failure). The runner
has no such constraint and logs to stdout like the rest of its output.

`wait_for_revision_state <rev> <state>` remains for test scripts that assert a *specific* revision
reaching a *specific* state mid-test (rev → `READY` → state); it is a narrower assertion, not a
come-back fence, and it is not a substitute for `wait_for_target_ready` after a power cycle.

## Logging

Every external call the runner makes — `pvcontrol`, `pvr`, and target-side `curl` — is preceded by a
`pvtest_log` line (`DEBUG` for routine steps, `INFO` for milestones) so a run log shows exactly what was
executed against the device and when. `pvcontrol cmd …` calls (e.g. `poweroff`) go through the
`pv_ctrl` wrapper, which logs and retries on transient `503` (command-slot busy) responses. This
convention applies to the runner orchestration only — not to the individual `resources/test` scripts,
whose stdout is diffed against golden output. Helpers shared by both (the
[readiness fence](#waiting-for-a-target-to-come-up)) need no special casing: `pvtest_log` picks the
safe channel per context, as described above.

All three log sources — `test.docker.sh` on the host, `pvtest-run` on the tester, and pantavisor on
the device — stamp lines with **Unix epoch seconds**, so the device logs tee'd into a `test.log`
interleave on the same time base as the framework's own lines and `pv-analyze-timestamps.sh` can
measure gaps across both. Pantavisor defaults to seconds-since-boot instead, so the harness boots
every container with `PV_LOG_TIMESTAMP=absolute`; a real device needs the same key in the config its
manifest `config=` line points at, otherwise its console lines carry an unrelated time base.
