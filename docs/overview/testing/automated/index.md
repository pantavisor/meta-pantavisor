---
title: "Automated Testing"
sidebar_position: 1
---
# The pvtest Harness

pvtest runs a single suite of tests against three kinds of target without a separate
suite per target:

- a single **appengine** container (the classic local/CI path),
- a **slot pool** of up to `-p` appengine containers driven in parallel,
- a **real device** over the network.

All three are the same machinery: one tester holding `-p` slots, each slot holding one
target. They differ only in how a slot's target is obtained and re-typed, which is what
[Assignment models](#assignment-models) describes.

This page covers the framework itself — how it is built, how it is laid out, how a run
executes and how to read its output. For running and authoring against the appengine
pool see [appengine.md](appengine.md); for real hardware see [devices.md](devices.md);
for what is implemented and what is not, [pvtest-list.md](pvtest-list.md).

For driving an appengine container by hand, with no harness involved, see
[Manual Testing](../manual/index.md).

## Architecture

The framework is split into a thin **`pantavisor-tester`** container (the runner:
`pvtest-run`, `pvr`, `jq`, `curl`, `valgrind`) and one or more device-like
**`pantavisor-appengine`** containers that expose SSH and the pvr HTTP API exactly as a
real device would. The tester drives each target over two channels:

- **`PVTEST_EXEC`** — a command prefix (typically `ssh …`) used to run
  `pvcontrol`/`pventer` on the target. The `pvcontrol()`/`pventer()`/`pvcurl()` wrappers
  in `pvtest/utils` route through it; when unset, commands run locally.
  A device manifest's `exec=ssh …` must include
  `-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2`:
  reboot-class updates black-hole established TCP connections, and an ssh without
  keepalives blocks on them forever. As a backstop, `pv_exec` wall-bounds every
  forwarded call tester-side with `timeout` (`PVTEST_EXEC_TIMEOUT`, default 60 s; 600 s
  for `pvtx` tarball streaming).
- **`PVTEST_HOST`** — the host for the target's pvr HTTP endpoint
  (`http://$PVTEST_HOST:12368/cgi-bin/pvr`), used by `pvr`/`curl` to deploy revisions.

Both are set automatically by the runner (per slot, rebuilt each time a slot re-types);
they are never set by the user.

### Where the code lives

Everything is in this layer, under `recipes-pv/pantavisor-pvtests/`:

| Path | Role | Ships as |
|---|---|---|
| `files/pvtest/pvtest-run` | the runner, drives a target from inside the tester container | `pantavisor-pvtest-runner` package → `/usr/bin/pvtest-run` |
| `files/pvtest/utils` | library sourced by `pvtest-run` and by every test's `resources/test` | same package → `/usr/share/pantavisor/pvtest/utils` |
| `files/pvtest/common` | helpers shared by the runner *and* the host orchestrator | same package, plus the tarball root |
| `files/host/test.docker.sh` | the host orchestrator, runs outside every container | deployed to the distro tarball root |
| `files/host/devices.txt` | `--devices` manifest template | tarball root |
| `files/host/README.md` | quick reference inside the tarball | tarball root |
| `files/data/local/`, `files/data/remote/` | the test suites | tarball root as `local/` and `remote/` |

`test.docker.sh` cannot source `utils`: it runs on the host, and `utils` defines
`pvcontrol`/`pventer`/`pvcurl`/`pvtx` shell functions that shadow real commands to route
them through `$PVTEST_EXEC`. Only the context-free helpers (`pvtest_log`,
`wait_for_status`, `pvtest_ssh_cmd`, `pvtest_normalize_cfg`) live in `common`, which both
halves source.

## Assignment models

Every non-interactive run works the same way: `test.docker.sh` builds one flat queue and
starts one tester, and `pvtest-run`'s `run_slot_pool` fans that queue out across `-p`
workers, each holding one target at a time. Two independent variables shape what a worker
does — and a real device is *not* a third path, it is a target with a different re-type
mechanism.

### Lifecycle — `--model`

How long a worker keeps a target.

**persistent** (the default) runs every test under exactly its `config.env`. Each worker
keeps ONE storage for the whole pass and re-boots with new config only when a test
actually needs it, merged into that test's own setup power cycle. Each test starts from
its own fresh child of the factory revision installed by `setup_test`, followed by a
synchronous gc.

**volatile** gives every test its own appengine container (own storage, thrown away
afterwards). Incompatible with `--devices` — you cannot throw a board away — and, for now,
with `-n`. Because the container is discarded anyway, the test's revision is seeded into
`pv-appengine`'s first-boot pvtx (the image's `pvtx.d` plus the test's tarballs staged at
`pvtx.extra.d`) and deployed under the same `locals/<id>` name, so the container boots into
it already committed. Pantavisor only auto-commits the revision it boots into when that
revision is literally named `0`, so `pv-appengine` also writes the `.pv/done` and
`.pv/progress` markers that path would have written — without them the revision comes up
with no progress at all and never reaches `DONE`. That is what makes the model cheap: no
install and no commit reboot, one pantavisor boot per test rather than three.

No factory revision is deployed under volatile — it would never be booted or cloned, and
the first gc reclaims it anyway — so a volatile test starts against a trail holding exactly
its own revision, where a persistent one starts against a trail that has accumulated the
worker's earlier tests.

Want results from both models? Run `test.docker.sh` twice, once per `--model`.

### Capability — `PVTEST_RETYPE`

How a target changes config, and whether releasing it destroys it. The host works this out
from the run and announces it; the tester never asks what kind of thing it is talking to.

| value | target | a test needing a different `config.env` | release |
|-------|--------|------------------------------------------|---------|
| `container` | appengine pool | powered off, then booted as a new generation | destroys it |
| `hook` | `--devices` board with `hook=` in its manifest | the hook power-cycles the board | leaves it up, reset to factory |
| `none` | board without `hook=`; preset `PVTEST_EXEC` | SKIPPED — no way to apply it | leaves it up, reset to factory |

The courtesy factory reset at detach follows the *release* column, not the target's
nature: a container skips it because nobody will ever see that container again.

`--model volatile` therefore requires `PVTEST_RETYPE=container`, which is why it and
`--devices` are mutually exclusive. Everything else composes freely.

## Topology

The tester is **always x86 and always runs on the host/CI runner** in both modes. What
changes is the target: an appengine pool runs *on the same host* (also x86), whereas a real
device is *external* and may be another architecture.

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

The device console arrives over its serial `tty` (read directly on the host, the same
convention `docker logs -f` uses for an appengine) and is captured to `<name>.log`.

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

The diagram shows one slot's lifecycle under `--model persistent`. The slot pool runs `-p`
of these in parallel over one global queue, pre-sorted for persistent only (claim-needing
tests first, equal configs adjacent — volatile has neither claims to batch nor re-types to
avoid, so it keeps the caller's order). A worker attaches its slot to a target running its
first test's config and inits it once; from there `setup_test` owns everything per test,
including the config change. When a test needs a different `config.env`, `setup_test` asks
the host to re-type the slot — for a container that means powering it off and booting a new
generation with the new `PV_*` env **on the same storage**, so it boots straight into the
pending test revision and the config change and the commit reboot cost a single power
cycle. Claim state is settled per test at the end of `setup_test`; a
claim persists on the worker's storage across adjacent claim tests (state-driven no-ops)
and is deleted at worker detach.

### Init device (once per attach)

`init_device` runs the [readiness fence](#waiting-for-a-target-to-come-up), collects device
info (`pvcontrol devmeta ls`), and clones + exports the factory revision the tests build on.
It runs when a worker first boots its slot's container (mid-setup re-types keep the factory
artifacts, re-keyed to the new container name); a container that fails init aborts the tests
stranded on that slot.

A mid-setup re-type is the same event — the host discards the container and boots a new
generation on the same storage — so it runs the same fence, only keyed on the pending test
revision reaching `DONE` instead of the current one. Skipping any of its stages there is what
used to make the first `pvr clone` of the following test race the freshly booted pvr endpoint.

### Install initial revision (before each test)

Each test's starting state is the device's **factory revision plus the tarballs declared in
its `test.json`**, installed by `setup_test` as the deterministically named revision
`locals/<test_id>` — a fresh child of the pristine factory clone, so tests never inherit each
other's state even on a storage that persists for the whole pass (a missing factory clone
aborts the test). Every tarball is a self-contained pvr *fragment* (a `json` state file +
`objects/`); the factory export + the app tarball(s) together form a complete revision.
`setup_test`:

1. waits for the device to settle from the previous test — `wait_for_current_settled`, which
   drains to a terminal step status and then waits for `READY` and the pvr endpoint, so the
   install below cannot race the pvr endpoint,
2. installs the revision with `pvtx` (begin empty, add factory export + tarballs, commit,
   run), falling back to a tester-side seeded-from-factory `pvr post --rev locals/<test_id>`
   when the device rootfs lacks `pvtx`,
3. `wait_for_target_ready` — the posted revision current with a terminal-good step status
   (`DONE` or `UPDATED`), then `READY` and the pvr endpoint,
4. takes at most ONE power cycle: a config mismatch re-types the container on the same
   storage (persistent pool; the new generation boots the pending revision and commits it),
   otherwise a still-pending (`UPDATED`) revision is committed with a plain reboot — then
   waits for `DONE`,
5. runs the synchronous garbage collector (`pvcontrol storage gc`) so the previous test's
   `locals/*` revisions are reclaimed; a `self-claim: "false"` test whose device is still
   claimed from a previous test is unclaimed **now, before go-remote** — with the Hub client
   down, a stale in-flight trail update cannot resume, so it can neither reject the unclaim
   (503 "update ongoing") nor apply over the just-installed revision — and then goes remote
   (a `locals/*` current revision otherwise drops the device to local mode; skipped when the
   config guarantees a rejection: `PV_CONTROL_REMOTE=0`, or already remote via
   `PV_CONTROL_REMOTE_ALWAYS=1`),
6. settles the claim state the test wants (`setup.self-claim`, `handle_self_claim`) — after
   go-remote so the Hub client is up, and on a committed `DONE` revision so an unclaimed
   device can walk register→claim; a device unclaimed in step 5 has its old Hub identity
   deleted here, once it is claimable again — and finally applies the test's usrmeta (local +
   Hub-side, which needs the claim already in place).

`setup_test` only *provisions*; the test body runs afterward in `exec_test`.

### Run test

`exec_test` runs the test's `resources/test` script (with `pvtest/utils` sourced so
`pvcontrol`/`pventer` route via `PVTEST_EXEC`), captures stdout, and `eval_test` diffs it
against the golden `output` file. In slot-pool mode, per-slot appengine logs are interleaved
into the per-test `test.log`.

### Teardown (per test, and at worker detach)

Per test, `teardown_test` removes the applied usrmeta (local + Hub) and, in the volatile
model only, deletes the test's self-claimed device (the container dies with the test). In the
persistent pool a claim survives re-types (it lives on the worker's storage) and is settled
per test by `handle_self_claim`; the worker's **final detach** cleans up for real: a device
that can still walk back to claimable is **unclaimed** first — after waiting for any
in-flight update to settle (pv rejects unclaim with 503 while one is ongoing),
`pvcontrol cmd unclaim` strips the creds from config/pantahub.config (reboot-free — the
device walks idle→register→claim on its own), the worker waits for `pantahub.state=claim`,
and only then deletes the device from the Hub, so a failed unclaim never leaves the device
Hub-deleted while still claimed on-device; otherwise it is deleted from the Hub directly.
Then the container gets a lenient `poweroff`. The container is discarded but its storage
lineage (`storage/<tag>/<key>/`) survives re-types within the pass. When running from the
interactive tester console, shutdown happens on console exit.

## Waiting for a target to come up

Every moment a target comes (back) up — first init, a pool re-type, a device hook re-type, a
reboot, a crash — goes through one fence,
`wait_for_target_ready [label] [rev] [status] [ready] [pvr]` (in `pvtest/utils`). Its stages
are waited in order and logged as they are reached, so a timeout names the stage that hung
instead of reporting a generic "device not ready":

1. **SSH** reachable (skipped when there is no `PVTEST_EXEC`), failing fast on a permanent
   auth error rather than polling the full timeout — this is what tells "the board/container
   is not up" apart from "pv-ctrl is not up",
2. **pv-ctrl** responsive (`pvcontrol devmeta ls`),
3. `rev` is the **current revision** (skipped when empty: whatever is current),
4. its **step status** is in the accepted set — `DONE` (a committed revision), `UPDATED` (a
   freshly applied local revision), or `DONE|UPDATED` for either; `ERROR`/`WONTGO` fail fast
   unless asked for,
5. `pantavisor.status` is **`READY`**,
6. the **pvr HTTP endpoint** on `:12368` answers — served by a *container*, so it comes up
   after `READY`. Which container provides it is target-specific and deliberately not
   checked: only the endpoint has to be there.

Stages 5 and 6 are not optional. "Ready" means the target can be driven, and everything that
drives one talks pv-ctrl and pvr; a target that never brings its containers up is not ready to
be tested, and continuing anyway only moves the failure somewhere less obvious. Because the
fence guarantees both, no caller has to fence either itself.

The fence always logs every stage, at `INFO`, with `ERROR` on the stage that failed — there
is no quiet mode, because there is no case where a stuck target is better diagnosed by saying
nothing. `label` is only a context prefix (`init`, `after crash 2`, …); pass one whenever a
run fences more than once, or the stage lines are identical and the log cannot say which fence
stalled.

`wait_for_revision_state <rev> <state>` remains for test scripts that assert a *specific*
revision reaching a *specific* state mid-test (rev → `READY` → state); it is a narrower
assertion, not a come-back fence, and it is not a substitute for `wait_for_target_ready` after
a power cycle.

## Logging

Every external call the runner makes — `pvcontrol`, `pvr`, and target-side `curl` — is
preceded by a `pvtest_log` line (`DEBUG` for routine steps, `INFO` for milestones) so a run
log shows exactly what was executed against the device and when. `pvcontrol cmd …` calls (e.g.
`poweroff`) go through the `pv_ctrl` wrapper, which logs and retries on transient `503`
(command-slot busy) responses. This convention applies to the runner orchestration only — not
to the individual `resources/test` scripts, whose stdout is diffed against golden output.

Inside the readiness fence, `_target_ready_log` sends its lines to stderr when no `label` is
set, so they reach `test.log` without polluting the stdout that is diffed against `output`.
Send a test's own diagnostics to stderr for the same reason.

All three log sources — `test.docker.sh` on the host, `pvtest-run` on the tester, and
pantavisor on the device — stamp lines with **Unix epoch seconds**, so the device logs tee'd
into a `test.log` interleave on the same time base as the framework's own lines and
`pv-analyze-timestamps.sh` can measure gaps across both. Pantavisor defaults to
seconds-since-boot instead, so the harness boots every container with
`PV_LOG_TIMESTAMP=absolute`; a real device needs the same key in the config its manifest
`config=` line points at, otherwise its console lines carry an unrelated time base.

## Build

Build the distro tarball as described in [get-started.md](../../get-started.md) — build
target `pantavisor-appengine-distro`.

When changes are made in meta-pantavisor (test scripts, `test.json`, expected output,
container recipes), a rebuild is required to pick them up. Because BitBake may not detect
file-level changes inside a recipe's `files/` directory, force a clean rebuild when touching
test data:

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'bitbake -c cleansstate pantavisor-pvtests-local pantavisor-pvtests-remote pantavisor-pvtests-host pantavisor-pvtest-runner pantavisor-appengine-distro pantavisor-bsp pantavisor-default-skel \
     && bitbake -c build pantavisor-appengine-distro'
```

## Install

Extract the tarball and load the Docker images as described in
[how-to-install/docker.md](../../../getting-started/how-to-install/docker.md). When working
directly on the build machine, the deploy directory already contains an unpacked directory —
cd into it and run `test.docker.sh` without extracting anything.

Remote tests require `PH_USER` and `PH_PASS` in the environment (or a sourced `.env` file).

### First-time system setup

On a fresh machine, install all required dependencies (Docker, QEMU, kernel modules, apt
packages) before running any tests:

```bash
./test.docker.sh install-deps
```

This is interactive and will prompt before making system changes. In CI set `CI_MODE=true` to
skip the prompt. You only need to run this once per machine; after that, `install-docker` is
sufficient when reinstalling from a new tarball.

The runner uses `sudo -n` (non-interactive) for several commands during test execution, so
those must be allowed without a password in sudoers. Add the following with `sudo visudo`:

```
<user> ALL=(ALL) NOPASSWD: /sbin/losetup, /sbin/modprobe, /usr/sbin/iw, /bin/chmod
```

## Workspace layout

```
<workspace>/
  run.log                           <- location info, one result line per test + inline diffs, SUMMARY
  README.md
  pvtest-tarballs.manifest          <- only when tarballs were substituted (see devices.md)
  <name>.log                        <- console capture per target
  results/
    <tag>/<scope>/<category>/<name>/
      test.log                      <- full bash-traced output + target console for this test
      diff                          <- diff (expected vs actual), present only when test failed
  storage/                          <- appengine mode only: full on-device storage per worker
  valgrind/                         <- appengine mode only, with -V
    <container>/valgrind.log.<pid>
```

A generated `README.md` inside each run workspace documents the full layout.

> **Note:** `storage/` is kept on disk for local debugging but is **not** uploaded to CI
> artifacts. `results/` (per-test logs, diffs) and valgrind results are uploaded.

## Interpreting results

The run prints location info at the start, then one result line per test (with inline diffs
for failures), and ends with a SUMMARY listing every test:

```
[pvtest] 1748000000 INFO -- launching 'local/core/legacy-config-overload'
[pvtest] 1748000023 INFO -- 'local/core/legacy-config-overload' PASSED (23 s)
[pvtest] 1748000110 ERROR -- 'local/lifecycle/reboot-nonreboot-rollback' FAILED (110 s)
--- diff: local/lifecycle/reboot-nonreboot-rollback ---
-expected line
+actual line
--- end diff ---
[pvtest] 1748000110 INFO -- 'local/runtime/remount-policies' SKIPPED
```

Result lines use a `[tag] UNIX_TIMESTAMP LEVEL -- [source]: message` format (matching
pantavisor's own log format). `INFO` for PASSED/SKIPPED/launching; `ERROR` for FAILED. The
launch line is printed before the test starts, letting you correlate parallel test timelines
by timestamp.

A failure means actual test output diverged from expected. Lines prefixed with `-` are
expected; lines prefixed with `+` are what the test produced. The diff is printed in `run.log`
immediately after the FAILED line, and also saved to `results/…/<name>/diff`.

### test.log

`test.log` is a single interleaved stream of everything that happened during a test attempt.
It mixes output from four sources:

**`test.docker.sh` (`set -x` traces)** — the host-side orchestrator running on the CI runner
or developer machine. Visible as `++ docker run ...`, `++ allocate_slot`, etc. Covers
container startup, loop device allocation, and concurrent slot management.

**`pvtest-run` (`set -x` traces) + `resources/test` output** — `pvtest-run` is the inner test
runner inside the tester container. It parses `test.json`, provisions the target, then runs
`resources/test` (with `set -x` injected at the top). The test script's stdout is captured and
diffed against the stored `output` file.

**`pv-appengine` (Pantavisor runtime launcher)** — runs inside the appengine container. Sets
up cgroups, loop devices, and storage mounts, then launches the `pantavisor` binary in a
restart loop to simulate device reboots between update steps.

**Pantavisor logs (`stdout_direct`)** — Pantavisor is started with
`PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct`. The `stdout_direct` mode streams Pantavisor's
internal log directly to stdout as each event happens, without buffering. These lines carry
the `[pantavisor] TIMESTAMP LEVEL -- [module]: message` format and are interleaved in real
time with the shell traces above.

Useful greps on a `test.log`:

```bash
# Pantavisor errors and warnings only
grep " ERROR\b\| WARN\b" test.log

# Just the test script execution (resources/test set -x traces)
grep "^+ \|^++ " test.log | tail -50
```

### Valgrind logs

With `-V`, each process gets its own `valgrind.log.<pid>` file. Pantavisor forks heavily via
LXC, so there will be many files. The main Pantavisor worker is typically the largest:

```bash
ls -S <workspace>/valgrind/<container>/ | head -3
grep -E "definitely lost|possibly lost|ERROR SUMMARY" valgrind.log.<largest-pid>
```

- `definitely lost` — real leaks, investigate
- `possibly lost` — typically PV buffer pools (`pv_buffer_init`); consistent across all tests
  at ~3.7 MB, not a regression
- `ERROR SUMMARY` — mostly `Syscall param` warnings from liblxc (`openat2`/`mount`), not
  pantavisor code
- No summary at the end of a file means the process was killed before valgrind finished
  flushing

## test.docker.sh flags reference

**Global options** (before the command):

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable debug output and print a results summary at the end |
| `-d <dir>`, `--dir <dir>` | Use `<dir>` as the pvtest source directory (overrides `PVTEST_DIR` env) |

**Commands**: `add`, `install-deps`, `install-docker`, `install-tarballs`, `ls`, `run`.

**`run` arguments** (after the path selector):

| Flag | Description |
|------|-------------|
| `-V`, `--valgrind` | Run Pantavisor under valgrind |
| `-p N`, `--parallel N` | Number of slots — the cap on concurrent appengine containers a single tester keeps busy. `-p 1` is fully serial. Incompatible with `-i` and `-m`. |
| `-i`, `--interactive` | Open a shell once Pantavisor reaches READY. Requires a specific leaf test path. |
| `-m`, `--manual` | Open a shell without starting Pantavisor. Use when PV fails to reach READY. |
| `-o`, `--overwrite` | Create or overwrite the expected test output |
| `-n`, `--netsim` | Enable wireless network simulation via `mac80211_hwsim` (experimental) |
| `-w PATH`, `--work PATH` | Set workspace path (default: mktemp) |
| `--fail-on-skip` | Exit non-zero if any test is SKIPPED, whatever the reason: a `test.json` `"skip":"true"`, a `"devices"` class the target isn't in, a config the live device doesn't satisfy, or missing Hub credentials. Used on CI/master. |
| `--model MODEL` | `persistent` (default) or `volatile`. See [Assignment models](#assignment-models). |
| `--devices FILE` | Run against one real device instead of the appengine pool. Incompatible with `-p>1`, `-m`, `-n`, `-V`. See [devices.md](devices.md). |

**Exit codes**: `0` = PASSED, `1` = FAILED, `2` = ABORTED
