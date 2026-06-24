# Automated Test Workflow

Structured testing using `test.docker.sh` — the test runner bundled inside the `pantavisor-appengine-distro` build target. Use this for collecting valgrind results and CI validation. For the manual development workflow (quick iteration while coding), including test plans, see [development-workflow.md](development-workflow.md).

## Build

Build the distro tarball as described in [how-to-build/get-started.md](../how-to-build/get-started.md) — build target `pantavisor-appengine-distro`.

When changes are made in meta-pantavisor (test scripts, `test.json`, expected output, container recipes), a rebuild is required to pick them up. Because BitBake may not detect file-level changes inside a recipe's `files/` directory, force a clean rebuild when touching test data:

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'bitbake -c cleansstate pantavisor-pvtests-local pantavisor-pvtests-remote pantavisor-appengine-distro pantavisor-bsp pantavisor-default-skel \
     && bitbake -c build pantavisor-appengine-distro'
```

For quicker iteration, you can also edit files directly inside an already-extracted workdir (e.g. `local/lifecycle/seq-non-reboot-updates/resources/test` or the `output` file) without rebuilding. Changes made this way are immediate but ephemeral — they must be ported back to the source tree under `recipes-pv/pantavisor-pvtests/files/local/` or `recipes-pv/pantavisor-pvtests/files/remote/` to become persistent.

## Install

Extract the tarball and load the Docker images as described in [how-to-install/docker.md](../how-to-install/docker.md). When working directly on the build machine, the deploy directory already contains an unpacked directory — cd into it and run `test.docker.sh` without extracting anything.

Remote tests require `PH_USER` and `PH_PASS` in the environment (or a sourced `.env` file).

## First-time system setup

On a fresh machine, install all required dependencies (Docker, QEMU, kernel modules, apt packages) before running any tests:

```bash
./test.docker.sh install-deps
```

This is interactive and will prompt before making system changes. In CI set `CI_MODE=true` to skip the prompt. You only need to run this once per machine; after that, `install-docker` is sufficient when reinstalling from a new tarball.

The runner uses `sudo -n` (non-interactive) for several commands during test execution, so those must be allowed without a password in sudoers. Add the following with `sudo visudo`:

```
<user> ALL=(ALL) NOPASSWD: /sbin/losetup, /sbin/modprobe, /usr/sbin/iw, /bin/chmod
```

## Running tests

```bash
# List available tests
./test.docker.sh -v ls

# Run a specific test (with valgrind)
./test.docker.sh -v run local/core/legacy-config-overload -V

# Run all tests in a category
./test.docker.sh -v run local/lifecycle -V

# Run all local or remote tests
./test.docker.sh -v run local -V
./test.docker.sh -v run remote -V

# Run all tests across all groups
./test.docker.sh -v run -V
```

The workspace is a temporary directory. Location info (workspace path, log paths) is printed at the start of the run and written to `run.log`. A copy of `run.log` is also saved to `./run.log` in the current directory for CI consumption.

## Workspace layout

```
<workspace>/
  run.log                           <- location info, one result line per test + inline diffs, SUMMARY
  README.md
  <scope>/<category>/<name>/        <- first attempt
    test.log                        <- full bash-traced output + docker output for this test
    diff                            <- diff (expected vs actual), present only when test failed
    valgrind/
      valgrind.log.<pid>            <- present only when run with -V
  <scope>/<category>/<name>.1/      <- retry attempt 1 (same structure)
  <scope>/<category>/<name>.2/      <- retry attempt 2 (same structure)
  storage/                          <- full Pantavisor on-device storage per test (same naming convention)
    <scope>/<category>/<name>/
      trails/ objects/ cache/ boot/ config/ logs/
```

> **Note:** `storage/` is kept on disk for local debugging but is **not** uploaded to CI artifacts. `local/` and `remote/` (with per-test logs, diffs, and valgrind results) are uploaded.

## Interpreting test results

The run prints location info at the start, then one result line per test (with inline diffs for failures), and ends with a SUMMARY listing every test:

```
Info: workspace=/tmp/pv_appengine.jBZqVz
Info: readme=/tmp/pv_appengine.jBZqVz/README.md
Info: run log=/tmp/pv_appengine.jBZqVz/run.log
Info: test log=/tmp/pv_appengine.jBZqVz/<scope>/<category>/<name>/test.log
Info: valgrind log=/tmp/pv_appengine.jBZqVz/<scope>/<category>/<name>/valgrind/valgrind.log.<pid>
Info: diff=/tmp/pv_appengine.jBZqVz/<scope>/<category>/<name>/diff

[pvtest] 1748000000 INFO -- launching 'local/core/legacy-config-overload'
[pvtest] 1748000000 INFO -- launching 'local/lifecycle/reboot-nonreboot-rollback'
[pvtest] 1748000023 INFO -- 'local/core/legacy-config-overload' PASSED (23 s)
[pvtest] 1748000110 ERROR -- 'local/lifecycle/reboot-nonreboot-rollback' FAILED (110 s)
--- diff: local/lifecycle/reboot-nonreboot-rollback ---
-expected line
+actual line
--- end diff ---
[pvtest] 1748000110 INFO -- 'local/runtime/remount-policies' SKIPPED
=======================================================
======================= SUMMARY =======================
=======================================================
[pvtest] 1748000023 INFO -- 'local/core/legacy-config-overload' PASSED (23 s)
[pvtest] 1748000110 ERROR -- 'local/lifecycle/reboot-nonreboot-rollback' FAILED (110 s)
[pvtest] 1748000110 INFO -- 'local/runtime/remount-policies' SKIPPED
=======================================================
```

Result lines use a `[pvtest] UNIX_TIMESTAMP LEVEL -- message` format (matching pantavisor's own log format). `INFO` for PASSED/SKIPPED/launching; `ERROR` for FAILED. The launch line is printed before the test starts, letting you correlate parallel test timelines by timestamp. With `-p N`, multiple launch lines appear together before any result lines arrive.

A failure means actual test output diverged from expected. Lines prefixed with `-` are expected; lines prefixed with `+` are what the test produced.

For failing tests, the diff is printed in `run.log` immediately after the FAILED line, and also saved to `<scope>/<category>/<name>/diff`. Retry attempts get their own directory (`<name>.1/`, `<name>.2/`).

### test.log

`test.log` is a single interleaved stream of everything that happened during a test attempt. It mixes output from four sources:

**`test.docker.sh` (`set -x` traces)**
The host-side orchestrator running on the CI runner or developer machine. Visible as `++ docker run ...`, `++ allocate_slot`, etc. Covers container startup, loop device allocation, and concurrent slot management.

**`pvtest-run` (`set -x` traces) + `resources/test` output**
`pvtest-run` is the inner test runner inside the tester container. It parses `test.json`, initialises storage, starts Pantavisor via `pv-appengine`, waits for it to reach READY, then runs `resources/test` (the actual test script, with `set -x` injected at the top). The test script's stdout is captured and diffed against the stored `output` file; the diff is written to `storage/<test_id>/diff` and copied to `<test_id>/diff` in the workspace.

**`pv-appengine` (Pantavisor runtime launcher)**
Runs inside the tester container. Sets up cgroups, loop devices, and storage mounts, then launches the `pantavisor` binary in a restart loop to simulate device reboots between update steps.

**Pantavisor logs (`stdout_direct`)**
Pantavisor is started with `PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct`. The `stdout_direct` output mode streams Pantavisor's internal log directly to stdout as each event happens, without buffering. These lines carry the `[pantavisor] TIMESTAMP LEVEL -- [module]: message` format and are interleaved in real time with the shell traces above. The same log content is also written to `storage/<scope>/<category>/<name>/logs/` (kept on disk, not in CI artifacts).

Useful greps on a `test.log`:

```bash
# Pantavisor errors and warnings only
grep " ERROR\b\| WARN\b" test.log

# Just the test script execution (resources/test set -x traces)
grep "^+ \|^++ " test.log | tail -50
```

### Valgrind logs

With `-V`, each process gets its own `valgrind.log.<pid>` file under `<scope>/<category>/<name>/valgrind/` (and `<name>.1/valgrind/` for retries). Pantavisor forks heavily via LXC, so there will be many files. The main Pantavisor worker is typically the largest:

```bash
ls -S <workspace>/local/lifecycle/reboot-nonreboot-rollback/valgrind/ | head -3
grep -E "definitely lost|possibly lost|ERROR SUMMARY" valgrind.log.<largest-pid>
```

- `definitely lost` — real leaks, investigate
- `possibly lost` — typically PV buffer pools (`pv_buffer_init`); consistent across all tests at ~3.7 MB, not a regression
- `ERROR SUMMARY` — mostly `Syscall param` warnings from liblxc (`openat2`/`mount`), not pantavisor code
- No summary at the end of a file means the process was killed before valgrind finished flushing

## Debugging a failing test

```bash
# Interactive shell — Pantavisor starts normally; shell opens once it reaches READY
# (and claims the device if credentials are configured).
# Use when Pantavisor boots fine but you want to inspect the running state.
./test.docker.sh -v run local/core/legacy-config-overload -i

# Manual shell — container starts but Pantavisor does NOT run.
# Use when Pantavisor fails to reach READY and you need to debug the startup sequence.
./test.docker.sh -v run local/core/legacy-config-overload -m
```

Both `-i` and `-m` require a specific leaf test path.

## Authoring and updating tests

### Adding a new test from scratch

Test data lives in the meta-pantavisor source tree under:

```
recipes-pv/pantavisor-pvtests/files/local/    # local tests
recipes-pv/pantavisor-pvtests/files/remote/   # remote tests
```

Each test is a directory at `<scope>/<category>/<name>/` containing `test.json`, `resources/test`, and an `output` file.

**1. Create the test directory** using the `add` command from the workdir:

```bash
# From the workdir (e.g. workdir/appengine-<commit>/):
./test.docker.sh add local/lifecycle/my-new-test
# Info: New test created at: .../local/lifecycle/my-new-test
```

This copies all templates (`test.json`, `resources/test`, `resources/ready`) and sets permissions. Once you have edited the test, port it back to the source tree:

```bash
cp -r <workdir>/local/lifecycle/my-new-test \
      recipes-pv/pantavisor-pvtests/files/local/lifecycle/
```

**2. Edit `test.json`:**

| Field | Purpose | Notes |
|-------|---------|-------|
| `#spec` | always `"pv-test@1"` | do not change |
| `description` | human-readable summary | keep it short |
| `setup.required-config` | the device config this test needs, as space-separated `KEY=VALUE`; the host boots a runner-type configured with exactly these keys (passed as `PV_*` env) and matches them against the device's live `pvcontrol conf ls`. A device runs the test only if its config satisfies every pair (empty matches any). Keep it as short as possible — prefer `setup.usrmeta` for keys configurable at runtime. | e.g. `"PV_CONTROL_REMOTE=0 PV_SECUREBOOT_MODE=lenient"` |
| `setup.usrmeta` | per-test runtime metadata, space-separated `KEY=VALUE`; applied one-by-one via `pvcontrol usrmeta save` after the initial revision is ready and removed in teardown | e.g. `"PV_LOG_PUSH=1 PH_UPDATER_INTERVAL=5"`; `""` if not needed |
| `setup.containers.control` | name of the container used as control plane | usually `"pvr-sdk"` |
| `setup.containers.tarballs` | list of container pvrexport tarballs | always include `bsp.tgz` and `pvr-sdk.tgz`; add extra containers as needed |
| `setup.containers.urls` | OTA container URLs (remote tests) | `[]` for local tests |
| `setup.self-claim` | `"true"`: claim the device in setup and delete it in teardown; `"false"`: ensure the device is unclaimed | requires `PH_USER`/`PH_PASS` when `"true"` |
| `test-script` | path to the test script | `"resources/test"` |
| `skip` | exclude test from runs | `"false"` normally; `"true"` to disable **for local iteration only** — `--fail-on-skip-field` (used on CI/master) turns `"true"` into a hard ERROR, so a skipped test must never be committed to master |

> The persistent-device model picks the runner from `setup.required-config`.
> Deprecated keys `setup.cmdline`, `setup.env`, `setup.pantavisor.config`,
> `setup.pvs`, and `setup.ready-script` are no longer read. The host derives one
> runner-type per distinct `(required-config, self-claim)` and boots it by passing
> the config keys as `PV_*` env — no static policy list; see the runner-fleet
> model below.

**3. Write `resources/test`:**

```sh
#!/bin/sh

source /usr/share/pantavisor/pvtest/utils

# Use pventer to run commands inside a container; stdout is diff-ed against `output`
pventer -c pvr-sdk pvcontrol config ls | jq -M -r '.["policy"]'
```

#### Test authoring rules

Tests run **sequentially against one shared device/trail and one shared tester
filesystem** (in pool mode, concurrently at `-p>1`). They must pass both run
individually and run together — so a test must never depend on, or leak into, the
state of another. The rules below are mandatory; they encode lessons that caused
real cross-test failures.

1. **Per-test isolation.** Any test that clones or uses `pvr` must clone into a
   unique per-test temp dir — never a fixed shared path like `/home/checkout`,
   `/home/remote`, `/home/local`, and never `rm -rf` a shared dir as a workaround:
   ```sh
   checkout="$(mktemp -d)/checkout"
   pvr clone http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr "$checkout" > /dev/null 2>&1 \
       || { echo "ERROR: pvr clone failed" >&2; exit 1; }
   cd "$checkout"
   ```
   **Do not override `$HOME`.** The harness exports a per-device, Hub-authenticated
   `$HOME` (`exec_test` runs `pvr login` into it), and `pvr post` / `pvr_post_rev`
   and every other Hub call read its `$HOME/.pvr/auth.json`. Clobbering `$HOME`
   (e.g. `export HOME="$(mktemp -d)"`) throws that token away, so Hub posts fail
   unauthenticated and `pvr_post_rev` returns empty. The per-device `$HOME` is
   already isolated per pool slot, so its object cache (`$HOME/.pvr/objects`) is
   safe to share across the sequential tests on one device. (A purely local test
   that never touches the Hub has no token to lose, but the temp-checkout pattern
   above is preferred everywhere and the only one that is safe for remote tests.)
2. **Clone source.** Clone the device's *current* state from its local pvr
   endpoint (`http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr`) — a clean
   baseline. Do **not** clone the accumulating Hub trail head
   (`https://api.pantahub.com/trails/$device_id`), which inherits other tests'
   leftovers.
3. **Clone safety.** Always guard the exit code and fail loud; suppress only
   stdout so it can't leak into the diffed output (as in the snippet above).
4. **Hub revisions: capture, never hardcode.** Hub revision numbers accumulate
   across the shared trail and are not fixed — never hardcode `"1"`/`"2"`. Post
   explicitly to the trail and capture the integer the Hub assigned with
   `pvr_post_rev` (from `utils`):
   ```sh
   device_id=$(_pv_exec cat /run/pantavisor/pv/device-id)
   trail_url="https://api.pantahub.com/trails/$device_id"
   rev=$(pvr_post_rev -m "msg" "$trail_url")
   [ -n "$rev" ] || { echo "ERROR: could not determine posted revision" >&2; exit 1; }
   wait_for_revision_state "pvr-sdk" "$rev" "UPDATED"
   ```
   Because the captured integer varies run-to-run, **mask it** wherever it appears
   in diffed stdout (e.g. `sed "s/\"$rev\"/\"REV\"/g"`).
5. **Local revisions: name them.** Post local revisions with a test-specific name
   (`pvr post --rev "locals/<name>"`) and wait with
   `wait_for_revision_state "pvr-sdk" "locals/<name>" "UPDATED|DONE"`.
6. **Output determinism.** Pipe JSON through `jq -M`, strip `\r`, and mask volatile
   fields (timestamps, PIDs, object hashes, `$HOME` paths, Hub rev integers). Never
   hand-edit `output` — regenerate it with `run … -o`.
7. **Clean up created state.** Device-meta / user-meta / signatures / objects a
   test creates persist on the shared device — delete them before the test ends,
   or assert deltas / filter to the test's own revisions rather than dumping
   absolute trail history.
8. **Containers / tarballs.** Declare containers in `test.json`
   `setup.containers.tarballs[]` (always include `bsp.tgz` + `pvr-sdk.tgz`). A new
   container = add a pvrexport `.tgz` and list it here (see "Adding a new container
   for a test" below).
9. **Runner-types.** A test selects its runner via `setup.required-config`. The
   host derives the runner-types automatically — one per distinct
   `(required-config, self-claim)` — and boots each by passing its config keys as
   `PV_*` env, so a new config combination needs **no** code change (just set it in
   `required-config`; keep it short). A test whose type could not be brought up is
   legitimately SKIPPED at runtime — that is **not** the same as the `skip` field
   below.
10. **`skip` is local-only.** `"skip":"true"` is fine for local developer
    iteration, but it must never reach master: CI/master runs pass
    `--fail-on-skip-field`, which turns a `skip:"true"` test into a hard ERROR.
    Tests that are not ready to run on master live in the [Todo list](#todo-list),
    not as skipped dirs in the tree.

Always source `utils` at the top (`source /usr/share/pantavisor/pvtest/utils`); it
provides `pvcontrol`/`pventer`/`pvcurl`, `_pv_exec`, the `wait_for_*` helpers and
`pvr_post_rev`.

**4. Generate the `output` file** (never edit manually):

```bash
./test.docker.sh -v run $SCOPE/$CATEGORY/$NAME -o
```

This writes `output` into the extracted workdir at `<workdir>/$SCOPE/$CATEGORY/$NAME/output`.

**5. Copy `output` back** to the source tree:

```bash
cp <workdir>/$SCOPE/$CATEGORY/$NAME/output \
   recipes-pv/pantavisor-pvtests/files/$SCOPE/$CATEGORY/$NAME/output
```

**6. Rebuild and verify** (see [Build](#build) above for the full cleansstate command):

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'bitbake -c cleansstate pantavisor-pvtests-local pantavisor-pvtests-remote pantavisor-appengine-distro \
     && bitbake -c build pantavisor-appengine-distro'
./test.docker.sh -v run $SCOPE/$CATEGORY/$NAME
```

Iterate between steps 4–6 until the test passes cleanly.

**7.** Add the test to the [test plan table](#test-plan) below and mark `[x]` in `TODO.md`.

### Updating expected output for an existing test

After a behaviour change makes an existing test fail with a known-good diff, regenerate its `output`:

```bash
./test.docker.sh -v run local/core/legacy-config-overload -o
cp <workdir>/local/core/legacy-config-overload/output \
   recipes-pv/pantavisor-pvtests/files/local/core/legacy-config-overload/output
```

Then rebuild and verify as above.

### Adding a new container for a test

When a test needs a container that does not exist yet in `local/common/tarballs/`:

**1. Create the recipe** in `recipes-containers/pv-examples/<name>.bb` — use `pv-example-app.bb` as a reference:

```bitbake
SUMMARY = "..."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
inherit image container-pvrexport
IMAGE_BASENAME = "<name>"
IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"
PVRIMAGE_AUTO_MDEV = "0"
SRC_URI += "file://<script>.sh"
install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/<script>.sh ${IMAGE_ROOTFS}${bindir}/<entrypoint>
}
ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/<entrypoint>"
```

**2. Register it in `recipes-pv/pantavisor/pantavisor-appengine-distro.bb`:**

Add to `do_create_tarball[depends]`:
```bitbake
do_create_tarball[depends] += "<name>:do_image_complete"
```

Add a copy block inside `do_create_tarball()`:
```bash
for f in ${DEPLOY_DIR_IMAGE}/<name>.pvrexport.tgz; do
    if [ -e "$f" ]; then
        cp -v "$f" "${STAGING_DIR}/local/common/tarballs/<name>.tgz"
        break
    fi
done
```

**3. Reference in `test.json`:**
```json
"tarballs": [
  "../../common/tarballs/bsp.tgz",
  "../../common/tarballs/pvr-sdk.tgz",
  "../../common/tarballs/<name>.tgz"
]
```

**4.** Rebuild as in step 6 above.

## test.docker.sh flags reference

**Global options** (before the command):

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable debug output and print a results summary at the end |
| `-d <dir>`, `--dir <dir>` | Use `<dir>` as the pvtest source directory (overrides `PVTEST_DIR` env) |

**`run` arguments** (after the path selector):

| Flag | Description |
|------|-------------|
| `-V`, `--valgrind` | Run Pantavisor under valgrind; results saved to `<tmpdir>/valgrind/` |
| `-p N`, `--parallel N` | Max runner instances per runner-type (default: 1). Incompatible with `-i` and `-m`. |
| `-P N`, `--max-instances N` | Global cap on concurrent runners across all types; types are scheduled in waves to stay under it (default: the value of `-p`). With `-p 1` the run is fully serial; with `-p 4` up to 4 runners run at once, like a shared pool. |
| `-i`, `--interactive` | Open a shell once Pantavisor reaches READY (device claimed if configured). Boots a single runner configured from the target test's `required-config`. Use to inspect a working system. Requires a specific leaf test path. |
| `-m`, `--manual` | Open a shell without starting Pantavisor; the container boots with the target test's `required-config` (as `PV_*` env). Use when PV fails to reach READY and you need to debug startup. |
| `-o`, `--overwrite` | Create or overwrite the expected test output (use when authoring or updating tests) |
| `-n`, `--netsim` | Enable wireless network simulation via `mac80211_hwsim` (experimental) |
| `-r N`, `--retry N` | Retry failed tests up to N times (default: 0) |
| `--fail-on-skip` | Exit non-zero if any test is SKIPPED at runtime (e.g. its runner-type could not be brought up) |
| `--fail-on-skip-field` | Treat a `test.json` `"skip":"true"` as a hard ERROR. Use on CI/master so a skipped test cannot land. |

**Exit codes**: `0` = PASSED, `1` = FAILED, `2` = ABORTED

### Parallel execution

Tests are grouped into runner-types by their `(required-config, self-claim)`. Each
type boots up to `-p` appengine runners; types are scheduled in waves bounded by the
global cap `-P` (default: the value of `-p`). One tester (`pvtest-run`) runs per wave
and dispatches each test to an idle runner of its type, so every test runs exactly
once and runners of different types execute concurrently.

```bash
./test.docker.sh run local -p 2
```

A runner that frees up immediately picks the next queued test of its type, so there is
no artificial delay. `-p 1` runs fully serial (global cap 1); raise `-p`/`-P` to widen
concurrency. The practical limit on a development machine is around 2–4 simultaneous
Docker+LXC stacks before the 30 s pantavisor startup timeout is at risk.

`-p N` is incompatible with `-i` (interactive) and `-m` (manual), which require a single test to be running.

---

## Todo list

Tests are organized by scope (`local` / `remote`) and category. The table below tracks implementation status.

### local — local experience tests

Local experience tests exercise Pantavisor features that operate without any cloud connectivity. These tests cover the ctrl server's unix socket API, container lifecycle, runtime behavior, security policies, and local services.

#### core

*Core Pantavisor initialization: config loading, config validation, namespace setup.*

| Test | Description | Done |
|------|-------------|------|
| `local/core/legacy-config-overload` | Legacy configuration overload | ✓ |
| `local/core/modern-config-overload` | Modern configuration overload (Env/Cmdline) | ✓ |
| `local/core/invalid-config-values` | Invalid Configuration Values Handling | |
| `local/core/rootfs-namespace` | Rootfs namespace (mounts, symlinks, etc.) | |

#### lifecycle

*Container and revision lifecycle: updates (reboot/non-reboot), rollback, auto-recovery, power-loss safety.*

| Test | Description | Done |
|------|-------------|------|
| `local/lifecycle/reboot-nonreboot-rollback` | Reboot, non-reboot and rollback updates | ✓ |
| `local/lifecycle/seq-non-reboot-updates` | Sequential non-reboot updates | ✓ |
| `local/lifecycle/power-loss-during-update` | Power Loss During Update | |
| `local/lifecycle/shared-object-restart-policies` | Shared object update with distinct restart policies | |
| `local/lifecycle/auto-recovery-restart` | Auto-recovery restart on failure | |
| `local/lifecycle/auto-recovery-retries-rollback` | Auto-recovery retries exhaustion during TESTING triggers rollback | |
| `local/lifecycle/auto-recovery-stable-timeout` | Auto-recovery stable timeout holds commit | |
| `local/lifecycle/auto-recovery-never-stops` | Auto-recovery policy never stops container after retries | |
| `local/lifecycle/auto-recovery-stabilize` | Stabilize pattern: container fails N times then becomes stable | |
| `local/lifecycle/auto-recovery-always-restart` | Always-restart policy on any exit code | |
| `local/lifecycle/auto-recovery-group-inheritance` | Group-level auto-recovery policy inherited by containers | |
| `local/lifecycle/auto-recovery-container-override` | Container auto-recovery overrides group (all-or-nothing) | |
| `local/lifecycle/auto-recovery-backoff-duration` | Backoff duration resets retry cycle after exhaustion | |

#### runtime

*Container runtime behavior: state JSON handling, groups, storage persistence, exports, remount policies.*

| Test | Description | Done |
|------|-------------|------|
| `local/runtime/invalid-state-json` | Invalid State JSON | |
| `local/runtime/large-state-json` | Large State JSON (100+ containers) | |
| `local/runtime/container-groups-startup` | Container Groups and Startup Order | |
| `local/runtime/container-storage-persistence` | Container Storage Persistence | |
| `local/runtime/config-overlay` | Configuration Overlay | |
| `local/runtime/resource-constraints` | Resource Constraints (CPU/Mem) | |
| `local/runtime/status-goal-success-failure` | Status Goal Success and Failure | ✓ |
| `local/runtime/container-exports` | Container Exports to Host | |
| `local/runtime/remount-policies` | Remount Policies (PV_REMOUNT_POLICY) | |
| `local/runtime/objects-crud` | Object store put/get/verify (pv-ctrl) | ✓ |
| `local/runtime/steps-rw` | Step read + local revision put (pv-ctrl) | ✓ |
| `local/runtime/invalid-signal-handling` | Invalid Signal Handling | |

#### control

*Tests that target the pv-ctrl unix socket API in a general way. Other categories may also use pv-ctrl, but for a specific subsystem rather than the API surface itself.*

| Test | Description | Done |
|------|-------------|------|
| `local/control/basic-endpoints` | Basic Endpoints (Containers, Objects, etc.) | ✓ |
| `local/control/basic-endpoints-curl` | Basic Endpoints via cURL | ✓ |
| `local/control/status-codes` | HTTP status-code contract (commands, signals, drivers, buildinfo) | ✓ |
| `local/control/pvcontrol-responsiveness` | pvcontrol responds normally during a time-consuming local operation (e.g. object transfer, sequential update) | |

#### xconnect

*xconnect service mesh: proxying, identity headers, D-Bus mediation, DRM, and Wayland isolation.*

| Test | Description | Done |
|------|-------------|------|
| `local/xconnect/unix-sockets` | Unix Sockets (UDS proxying) | |
| `local/xconnect/rest-over-uds` | REST-over-UDS (Identity headers) | |
| `local/xconnect/dbus` | D-Bus (Policy mediation) | |
| `local/xconnect/drm` | DRM (Graphics node injection) | |
| `local/xconnect/wayland` | Wayland (Isolated UI rendering) | |

#### security

*Security policies: secure boot, OEM key validation, container roles, object checksum verification, encrypted storage.*

| Test | Description | Done |
|------|-------------|------|
| `local/security/strict-secure-boot` | Strict Secure Boot (Unsigned rejection) | ✓ |
| `local/security/container-roles` | Container Roles (mgmt vs nobody access) | ✓ |
| `local/security/oem-secureboot` | OEM Secureboot (OEM key validation) | ✓ |
| `local/security/object-checksum` | Object Checksum Validation | ✓ |
| `local/security/lenient-secure-boot` | Lenient Secure Boot | |
| `local/security/encrypted-storage` | Encrypted Storage (LUKS/dm-crypt) | |
| `local/security/secureboot-sig-0x30` | Secure Boot when signature starts with 0x30 | |

#### services

*On-device services: garbage collection, logging, SSH, metadata manipulation, tsh daemon, IPAM, and other auxiliary features.*

| Test | Description | Done |
|------|-------------|------|
| `local/services/log-output-formats` | Log Output Formats (filetree/singlefile) | |
| `local/services/on-demand-gc` | On-Demand Garbage Collection | ✓ |
| `local/services/daemons` | Daemon list/stop/start (pv-ctrl) | ✓ |
| `local/services/metadata-crud` | Device/user metadata CRUD (pv-ctrl) | ✓ |
| `local/services/tsh-daemon` | tsh daemon management & log capture | |
| `local/services/log-rotation` | Log rotation functionality | |
| `local/services/ssh-override` | SSH Override | |
| `local/services/metadata-manipulation` | Metadata Manipulation | |
| `local/services/ipam-single-pool` | Single IPAM pool — container gets IP from pool | |
| `local/services/ipam-multi-pool` | Two IPAM pools — correct address assignment | |
| `local/services/ipam-collision` | Conflicting pool addresses detected and rejected | |
| `local/services/ipam-invalid` | Invalid IPAM config rejected gracefully | |
| `local/services/ipam-lxcbr` | IPAM with lxcbr bridge networking | |

---

### remote — remote experience tests

Remote experience tests require an active Pantacor Hub connection and exercise the device-cloud communication layer: initial claiming, revision delivery, cloud status reporting, and remote services.

#### core

*Core remote initialization: pantahub.config parsing (encrypted and unencrypted).*

| Test | Description | Done |
|------|-------------|------|
| `remote/core/encrypted-pantahub-config` | Encrypted `pantahub.config` handling | ✓ |
| `remote/core/unencrypted-pantahub-config` | Unencrypted `pantahub.config` handling | |

#### lifecycle

*Cloud-driven revision lifecycle: simultaneous updates, disk-space handling, cloud rollback status, retry logic.*

| Test | Description | Done |
|------|-------------|------|
| `remote/lifecycle/simultaneous-updates` | Successful Multiple Simultaneous Remote Updates | ✓ |
| `remote/lifecycle/insufficient-disk-space` | Update with Insufficient Disk Space | ✓ |
| `remote/lifecycle/rollback-cloud-status` | Trigger rollback and verify cloud status | ✓ |
| `remote/lifecycle/update-retries-pv-crash` | Update retries when PV crashes | ✓ |
| `remote/lifecycle/update-retries-gc-pressure` | Update retries when PV crashes with GC pressure | ✓ |
| `remote/lifecycle/claim-after-local-updates` | Claim after local updates with random artifacts | |

#### control

*Tests that target Pantacor Hub communication in a general way. Other categories also use hub communication, but for their specific purpose (revision delivery, log push, etc.).*

| Test | Description | Done |
|------|-------------|------|
| `remote/control/manual-claim` | Manual Device Claim | ✓ |
| `remote/control/auto-claim` | Automatic Device Claim | ✓ |
| `remote/control/always-remote-disabled` | Always Remote Disabled | ✓ |
| `remote/control/always-remote-enabled` | Always Remote Enabled | ✓ |
| `remote/control/pvcontrol-responsiveness` | pvcontrol responds normally during a Pantahub download or other expensive remote operation | |

#### services

*Cloud-integrated services: log push, metadata exchange, and other hub-backed features.*

| Test | Description | Done |
|------|-------------|------|
| `remote/services/ph-logger-cloud-push` | `ph-logger` cloud push | ✓ |
| `remote/control/device-user-metadata` | Device/User Metadata Exchange | ✓ |

