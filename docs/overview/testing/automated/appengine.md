---
sidebar_position: 2
---
# Running and Authoring pvtests (appengine)

The appengine pool is the default target: x86 containers running on the same host as the
tester. This page covers installing the distro, running the suite against the pool, debugging
a failure, authoring tests, and how CI drives the same thing. For the framework itself see
[index.md](index.md); for real hardware, [device.md](device.md).

## Install

Extract the tarball and load the Docker images as described in the tarball's own `README.md`.
When working directly on the build machine, the deploy directory already holds the unpacked
tree — cd into it and run `test.docker.sh` without extracting anything.

## Running tests

`./test.docker.sh -h` lists every command, flag, path selector and environment override. The
tarball `README.md` has ready-made examples.

## Debugging a failing test

Every run creates a workspace with a `README.md` inside that documents the full layout, the
log format and its four sources, the useful greps, and how to read valgrind output. Besides
that, pvtest provides interactive and manual modes for the appengine target.

Interactive mode opens a console in the tester container and, in parallel, starts an appengine
container instance. From that console the device is reachable and the full test script can be
run by hand.

```bash
./test.docker.sh run local/core/legacy-config-overload -i
```

Manual mode opens a console in the appengine container without starting Pantavisor, which is
handy to start Pantavisor by hand when it crashes or fails to reach READY.

```bash
./test.docker.sh -v run local/core/legacy-config-overload -m
```

## Adding a new test

Test data lives in the meta-pantavisor source tree under:

```
recipes-pv/pantavisor-pvtests/files/local/    # local tests
recipes-pv/pantavisor-pvtests/files/remote/   # remote tests
```

Each test is a directory at `<scope>/<category>/<name>/` containing `test.json`,
`resources/test`, and an `output` file.

**1. Create the test directory** using the `add` command from the workdir:

```bash
# From the workdir (e.g. workdir/appengine-<commit>/):
./test.docker.sh add local/lifecycle/my-new-test
# Info: New test created at: .../local/lifecycle/my-new-test
```

This copies all templates (`test.json`, `resources/test`, `resources/ready`) and sets
permissions.

**2. Edit `test.json`:**

| Field | Purpose | Notes |
|-------|---------|-------|
| `#spec` | always `"pv-test@1"` | do not change |
| `description` | human-readable summary | keep it short |
| `setup.config.env` | per-test env config, as space-separated `KEY=VALUE`. Prefer `setup.config.usrmeta` for keys configurable at runtime | e.g. `"PV_CONTROL_REMOTE=0 PV_SECUREBOOT_MODE=lenient"` |
| `setup.config.usrmeta` | per-test runtime metadata, space-separated `KEY=VALUE` | e.g. `"PV_LOG_PUSH=1 PH_UPDATER_INTERVAL=5"` |
| `setup.containers.tarballs` | list of extra container pvrexport tarballs merged on top of the device's factory state to form the test's initial revision | the device/appengine should provide bsp plus a container with the pvr endpoint (e.g. pvr-sdk), so do not add those |
| `setup.self-claim` | `"true"`: claim the device in setup and delete it in teardown; `"false"`: ensure the device is unclaimed in setup | requires `PH_USER`/`PH_PASS` when `"true"` |
| `setup.commit-initial` | whether the initial revision must be committed as a rollback point before the test body runs | `"true"` costs a full reboot cycle, so set it only when the test triggers a rollback that must land on its own revision, or asserts the initial revision survives a gc. Only affects the persistent model |
| `test-script` | path to the test script | `"resources/test"` |
| `skip` | exclude test from runs | `--fail-on-skip` (used on CI/master) fails the run on any SKIPPED |
| `devices` | allow-list of the target *classes* (`type=` in the device manifest) this test may run on | `[]` (run everywhere) |

**3. Write `resources/test`:**

```sh
#!/bin/sh

source /usr/share/pantavisor/pvtest/utils

# pvcontrol talks to the device's pv-ctrl directly; stdout is diff-ed against `output`
pvcontrol conf ls | jq -M -r '.["policy"]'
```

**4. Generate `output`:**

Once `test.json` and `resources/test` are filled in, generate the golden output:

```bash
./test.docker.sh run local/lifecycle/my-new-test -o
```

**5. Port it to the source tree:**

Once you have edited the test, port it back to the source tree:

```bash
cp -r <workdir>/local/lifecycle/my-new-test \
      recipes-pv/pantavisor-pvtests/files/local/lifecycle/
```

**6. Rebuild and verify** — see [index.md](index.md#build) for the full cleansstate command,
then re-run the test. Iterate between steps 4–6 until it passes cleanly.

**7.** Mark the test in [pvtest-list.md](pvtest-list.md) and in `TODO.md`.

### Adding a new container for a test

When a test needs a container that does not exist yet in the target trees:

**1. Create the recipe** in `recipes-containers/pv-examples/<name>.bb` — use
`pv-example-app.bb` as a reference:

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

**2. Register it in `recipes-pv/pantavisor/pantavisor-appengine-distro.bb`** by adding the
name to `PV_PVTEST_CONTAINERS`:

```bitbake
PV_PVTEST_CONTAINERS ?= "pv-example-app pv-example-norole ... <name>"
```

That one list drives both `do_create_tarball[depends]` and the staging loop, so there is
nothing else to keep in sync. Use `PV_PVTEST_CONTAINERS_XCONNECT` instead if the container
only exists when `PANTAVISOR_FEATURES` carries `xconnect-dbus-systembus` — and then pin the
test `"devices": ["appengine"]`, since a board build won't have it. Add the name to the `cp`
into each target's `remote/` as well if remote tests need it.

**3. Reference in `test.json`** by its deploy name, relative to the scope root and never
naming a target — `test.docker.sh` mounts the active target's tarball tree over
`/work/<scope>/common/tarballs`, so one reference resolves to the right architecture on every
board (see [device.md](device.md#installing-target-tarballs)):

```json
"tarballs": [
  "../../common/tarballs/<name>.pvrexport.tgz"
]
```

**4.** Rebuild.

### Test authoring rules

Tests assigned to the same worker run **sequentially against one shared container's
device/trail and one shared tester filesystem** (the slot pool runs other workers
concurrently at `-p>1`). They must pass both individually and together — so a test must never
depend on, or leak into, the state of another. The rules below are mandatory; they encode
lessons that caused real cross-test failures.

1. **Per-test isolation.** Any test that clones or uses `pvr` must clone into a unique
   per-test temp dir — never a fixed shared path like `/home/checkout`, and never `rm -rf` a
   shared dir as a workaround:
   ```sh
   checkout="$(mktemp -d)/checkout"
   pvr_clone_local_or_die "$checkout"
   cd "$checkout"
   ```
   **Do not override `$HOME`.** The harness exports a per-device, Hub-authenticated `$HOME`
   (`exec_test` runs `pvr login` into it) whose `.pvr/auth.json` every Hub call reads;
   clobbering it makes `pvr post` / `pvr_post_rev` fail unauthenticated. It is already
   isolated per pool slot, so its object cache is safe to share.
2. **Clone source.** Clone the device's *current* state from its local pvr endpoint
   (`http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr`) — a clean baseline. Do **not**
   clone the accumulating Hub trail head, which inherits other tests' leftovers.
3. **Clone safety.** Always guard the exit code and fail loud; suppress only stdout so it
   can't leak into the diffed output.
4. **Hub revisions: capture, never hardcode.** Hub revision numbers accumulate across the
   shared trail — never hardcode `"1"`/`"2"`. Post explicitly and capture the integer the Hub
   assigned with `pvr_post_rev` (from `utils`):
   ```sh
   device_id=$(pv_exec cat /run/pantavisor/pv/device-id)
   trail_url="https://api.pantahub.com/trails/$device_id"
   rev=$(pvr_post_rev -m "msg" "$trail_url")
   [ -n "$rev" ] || { echo "ERROR: could not determine posted revision" >&2; exit 1; }
   wait_for_revision_state "$rev" "UPDATED"
   ```
   Because the captured integer varies run-to-run, **mask it** wherever it appears in diffed
   stdout (e.g. `sed "s/\"$rev\"/\"REV\"/g"`).
5. **Local revisions: name them.** Post local revisions with a test-specific name
   (`pvr post --rev "locals/<name>"`) and wait with
   `wait_for_revision_state "locals/<name>" "UPDATED|DONE"`.
6. **Output determinism.** Pipe JSON through `jq -M`, strip `\r`, and mask volatile fields
   (timestamps, PIDs, object hashes, `$HOME` paths, Hub rev integers). Never hand-edit
   `output` — regenerate it with `run … -o`.
7. **Clean up created state.** Device-meta / user-meta / signatures / objects a test creates
   persist on the shared device — delete them before the test ends, or assert deltas / filter
   to the test's own revisions rather than dumping absolute trail history.
8. **Containers / tarballs.** The initial revision is the device's factory clone plus the
   extra containers declared in `test.json` `setup.containers.tarballs[]` — never include
   `bsp.tgz`/`pvr-sdk.tgz` (the functional device provides its own baseline, which differs per
   target). A test that manipulates a container must bring its own (e.g.
   `pv-example-norole.tgz` for reboot-class updates, `pv-example-app.tgz` for non-reboot ones).
9. **Target pinning.** `"devices"` absent or `[]` means "run everywhere" — the default for
   almost every test. Pin only a test that *cannot* pass elsewhere: one whose golden output
   asserts the appengine baseline, or that needs a pantavisor build feature a given BSP
   doesn't ship. An entry matches `PVTEST_DEVICE_TYPE` — `appengine` for a container, a
   manifest's `type=` for real hardware. That is the target *class*, not the individual
   runner: a pin holds for every board of that kind. `PVTEST_DEVICE_NAME` is never matched
   here.
   ```
   "devices": ["appengine"]                # container only — asserts the appengine baseline
   "devices": ["appengine", "<machine>"]   # also on every board of that machine class
   ```
10. **`skip` is local-only.** `"skip":"true"` is fine for local developer iteration, but it
    must never reach master: CI/master runs pass `--fail-on-skip`, which fails the run on *any*
    SKIPPED result. Tests that are not ready to run on master live in
    [pvtest-list.md](pvtest-list.md), not as skipped dirs in the tree. This is not the same as
    a runtime SKIP: on a real device without a setbootconfig script, a test whose `config.env`
    the live device doesn't already satisfy is legitimately SKIPPED — see [device.md](device.md).
11. **Destructive tests must be state-independent.** There is no isolation mechanism — every
    test shares a container with later same-config tests, so a test that destroys device state
    (e.g. a GC test that deletes the factory revision `/storage/trails/0`, or one that fills
    the disk) must be written to run on a device in *any* prior state and must not assume a
    pristine factory. Build the baseline the test needs from its own posted revisions, derive
    content-addressed object names dynamically rather than hard-coding factory hashes, and
    assert only on paths the test itself creates/removes. See `local/services/on-demand-gc`
    and `remote/lifecycle/insufficient-disk-space`.
12. **Only stdout is compared.** The script's stderr goes to `test.log`, not the diffed
    output — a device BSP's tools may print noise there. A test that *asserts* on an error
    body (`pvcontrol` prints error responses to stderr) must merge it explicitly: plain `2>&1`
    when the tool is test-owned, or `2>&1 | grep -v '^INFO:'` when it is the device's own
    pvcontrol, whose noise would re-enter the diff.
13. **The script runs in the tester, the tools run on the target.** `pvcontrol`/`pvcurl`/
    `pventer` execute on the device, so a file argument must exist where the tool runs: stage
    tester files with `pv_stage_file` (clean up with `pv_unstage_file`), bring device-side
    output files back with `pv_fetch_file`.
14. **Don't lean on the device rootfs toolset.** A BSP's busybox can be trimmed (no
    `sha256sum`, no `cut`). Create and hash payloads in the tester, which always has the full
    toolset.
15. **Containers that write to `/tmp` must bring their own tmpfs.** An old BSP's lxc (3.x)
    mounts container rootfs overlays read-only, where newer lxc mounts them rw. A container
    whose payload writes to `/tmp` (e.g. in-container `pvcontrol`/`pvcurl`) must mount a tmpfs
    there via the `PV_LXC_EXTRA_CONF` template arg — see `pv-example-mgmt.args.json`.
16. **Never assert on a literal device baseline.** The container set, bsp object names, storage
    mount prefix and log line format are all target-dependent. Assert invariants or booleans
    about them (see `local/security/object-checksum`), or filter to content the test itself
    installs (see `local/security/container-roles`).
17. **Prefer shared utils to re-inventing the wheel.** Always source `utils` at the top
    (`source /usr/share/pantavisor/pvtest/utils`); it provides `pvcontrol`/`pventer`/`pvcurl`,
    `pv_exec`, the `wait_for_*` helpers, `pvr_clone_local_or_die` and `pvr_post_rev`. After a
    reboot or a `pv_crash`, fence the come-back with `wait_for_down` followed by
    `wait_for_target_ready`, passing a short label (`"after crash 2"`) whenever a test fences
    more than once — otherwise each fence logs the same lines and the log cannot say which
    one stalled.

## Updating expected output for an existing test

After a behaviour change makes an existing test fail with a known-good diff, regenerate its
`output`:

```bash
./test.docker.sh -v run local/core/legacy-config-overload -o
cp <workdir>/local/core/legacy-config-overload/output \
   recipes-pv/pantavisor-pvtests/files/local/core/legacy-config-overload/output
```

First, check the output has changed as expected, then rebuild and verify as above.

## CI

Three workflows under `.github/workflows/` drive the suite; all run the tests job on the
self-hosted `pvtest-runner` label, which has docker, loop devices and the `sudo -n`
allowances the tarball `README.md` asks for.

| Workflow | Trigger | What it runs |
|---|---|---|
| `call-pvtests.yaml` | reusable (`workflow_call`) | The actual run. Inputs: `commit`, `test_path`, `parallel` (default `6`), `model` (default `volatile`; `all` expands to a `["volatile","persistent"]` matrix). Downloads the distro artifact, `CI_MODE=true ./test.docker.sh install-docker`, then runs with `-V --fail-on-skip`. Remote scope always runs serial (no `-p`). Uploads the workspace as `pvtest-workspace-<sha7>-<test_path>-<model>`. |
| `manual-pvtests.yaml` | `workflow_dispatch` | Builds `pantavisor-appengine-distro` for `docker-x86_64`, then calls `call-pvtests.yaml` with the four inputs forwarded. |
| `schedule-pvtests.yaml` | nightly cron (02:00) + dispatch | Same build, then `parallel: 6`, `model: all` — the nightly covers both execution models. |

The uploaded workspace artifact carries `README.md`, `run.log`, `results/`, `valgrind/` and
the `*.log` console captures only: **`storage/` is deliberately excluded**, so a downloaded CI
workspace has no trails/objects/logs tree to inspect, unlike a local run. Workspaces are
model-scoped so the two matrix legs don't collide, and a cleanup step removes all
`pantavisor-appengine*` containers and images and both workspaces after each run.
