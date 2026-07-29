---
sidebar_position: 2
---
# Running and Authoring pvtests (appengine)

The appengine pool is the default target: containers on the same host as the tester, all
x86. This page covers running the suite against it, writing and updating tests, and how CI
drives the same thing. For the framework itself see [index.md](index.md); for real hardware,
[devices.md](devices.md).

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

The workspace is a temporary directory unless `-w` is given. Location info is printed at the
start of the run and written to `run.log`; a copy of `run.log` is also saved to `./run.log`
in the current directory for CI consumption.

### Parallel execution

A single long-lived tester (`pvtest-run`) owns a global FIFO of `-p` **slots** over one flat,
pre-sorted test queue (claim-needing tests first, then grouped by matching `config.env`, so
adjacent tests need the fewest re-types). Each slot maps to one appengine container and keeps
ONE persistent storage for its whole run. Each test's setup installs its initial revision and
then takes at most ONE power cycle: if the test's `config.env` no longer matches what's
loaded, it **re-types** — the host stops the old container and boots a new one with the new
`PV_*` env, same storage, straight into the pending revision — otherwise a plain reboot
commits the revision. The tester keeps every slot busy until the queue drains, so the only
idle is the genuine tail. Each test runs exactly once.

```bash
./test.docker.sh run local -p 2
```

`-p 1` runs fully serial. The practical limit on a development machine is around 2–4
simultaneous Docker+LXC stacks before the 30 s pantavisor startup timeout is at risk; CI runs
at `-p 6` on the dedicated runner.

`-p N` is incompatible with `-i` (interactive) and `-m` (manual), which require a single test
to be running.

The above describes `--model persistent`. `--model volatile` uses a different, non-re-typing
concurrency model: one fresh appengine container per test, capped at `-p` concurrent tests via
a semaphore, closer to "one `docker run` per test". Because the container is fresh and
discarded, the test's revision is built by `pv-appengine` on first boot rather than installed
afterwards, so a volatile test pays one pantavisor boot instead of the three a persistent test
pays (boot, install, commit reboot).

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

## Adding a new test

Test data lives in the meta-pantavisor source tree under:

```
recipes-pv/pantavisor-pvtests/files/data/local/    # local tests
recipes-pv/pantavisor-pvtests/files/data/remote/   # remote tests
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
permissions. Once you have edited the test, port it back to the source tree:

```bash
cp -r <workdir>/local/lifecycle/my-new-test \
      recipes-pv/pantavisor-pvtests/files/data/local/lifecycle/
```

**2. Edit `test.json`:**

| Field | Purpose | Notes |
|-------|---------|-------|
| `#spec` | always `"pv-test@1"` | do not change |
| `description` | human-readable summary | keep it short |
| `setup.config.env` | the device config this test needs, as space-separated `KEY=VALUE`; when the currently-loaded config doesn't already match, the test's setup re-types the slot to a container booted with exactly these keys (passed as `PV_*` env), merged into the initial revision's commit power cycle. Keep it as short as possible — prefer `setup.config.usrmeta` for keys configurable at runtime. | e.g. `"PV_CONTROL_REMOTE=0 PV_SECUREBOOT_MODE=lenient"` |
| `setup.config.usrmeta` | per-test runtime metadata, space-separated `KEY=VALUE`; applied one-by-one via `pvcontrol usrmeta save` after the initial revision is ready and removed in teardown | e.g. `"PV_LOG_PUSH=1 PH_UPDATER_INTERVAL=5"`; `""` if not needed |
| `setup.containers.tarballs` | list of extra container pvrexport tarballs merged on top of the device's factory state to form the test's initial revision | `[]` when the factory state is enough; add only the containers the test manipulates — never `bsp`/`pvr-sdk`, the functional device provides its own baseline |
| `setup.self-claim` | `"true"`: claim the device in setup and delete it in teardown; `"false"`: ensure the device is unclaimed | requires `PH_USER`/`PH_PASS` when `"true"` |
| `setup.commit-initial` | whether the initial revision must be committed as a rollback point before the test body runs. `"true"` costs a full reboot cycle — the single most expensive step of a test's setup — so set it only when the test needs it: it triggers a rollback that must land on its own revision, or it asserts the initial revision survives a gc (gc keeps `pv_done`). A test that only posts revisions and asserts on *those* does not need it | set explicitly on every test, even where it matches the default. Omitting it defaults to `"true"` for backwards compatibility. Only affects the persistent model: volatile boots into an already-committed revision |
| `test-script` | path to the test script | `"resources/test"` |
| `skip` | exclude test from runs | `"false"` normally; `"true"` to disable **for local iteration only** — it yields a SKIPPED result, and `--fail-on-skip` (used on CI/master) fails the run on any SKIPPED |
| `devices` | allow-list of the target *classes* this test may run on; an entry matches `PVTEST_DEVICE_TYPE` — `appengine` for the container, a device manifest's `type=` for real hardware | `[]` (run everywhere) for almost every test. Use it only when a test *cannot* pass elsewhere. See [devices.md](devices.md) |

> The slot-pool model picks a slot's config from `setup.config.env`. Deprecated keys
> `setup.required-config`, `setup.usrmeta`, `setup.cmdline`, `setup.env`,
> `setup.pantavisor.config`, `setup.pvs`, `setup.ready-script`, `setup.containers.control`,
> and `setup.containers.urls` are no longer read. The host boots a slot's container by passing
> the config keys as `PV_*` env — no static policy list.

**3. Write `resources/test`:**

```sh
#!/bin/sh

source /usr/share/pantavisor/pvtest/utils

# pvcontrol talks to the device's pv-ctrl directly; stdout is diff-ed against `output`
pvcontrol conf ls | jq -M -r '.["policy"]'
```

### Test authoring rules

Tests assigned to the same worker run **sequentially against one shared container's
device/trail and one shared tester filesystem** (the slot pool runs other workers
concurrently at `-p>1`). They must pass both run individually and run together — so a test
must never depend on, or leak into, the state of another. The rules below are mandatory; they
encode lessons that caused real cross-test failures.

1. **Per-test isolation.** Any test that clones or uses `pvr` must clone into a unique
   per-test temp dir — never a fixed shared path like `/home/checkout`, and never `rm -rf` a
   shared dir as a workaround:
   ```sh
   checkout="$(mktemp -d)/checkout"
   pvr_clone_local_or_die "$checkout"
   cd "$checkout"
   ```
   **Do not override `$HOME`.** The harness exports a per-device, Hub-authenticated `$HOME`
   (`exec_test` runs `pvr login` into it), and `pvr post` / `pvr_post_rev` and every other Hub
   call read its `$HOME/.pvr/auth.json`. Clobbering `$HOME` throws that token away, so Hub
   posts fail unauthenticated and `pvr_post_rev` returns empty. The per-device `$HOME` is
   already isolated per pool slot, so its object cache is safe to share across the sequential
   tests on one device.
2. **Clone source.** Clone the device's *current* state from its local pvr endpoint
   (`http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr`) — a clean baseline. Do **not** clone
   the accumulating Hub trail head, which inherits other tests' leftovers.
3. **Clone safety.** Always guard the exit code and fail loud; suppress only stdout so it
   can't leak into the diffed output.
4. **Hub revisions: capture, never hardcode.** Hub revision numbers accumulate across the
   shared trail and are not fixed — never hardcode `"1"`/`"2"`. Post explicitly and capture
   the integer the Hub assigned with `pvr_post_rev` (from `utils`):
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
9. **Config selection.** A test selects its target's config via `setup.config.env`. The host
   boots/re-types a worker's container by passing those config keys as `PV_*` env, so a new
   config combination needs **no** code change. On a real device without a re-type hook, a test
   whose config the live device doesn't already satisfy is legitimately SKIPPED at runtime —
   that is **not** the same as the `skip` field below.
10. **`skip` is local-only.** `"skip":"true"` is fine for local developer iteration, but it
    must never reach master: CI/master runs pass `--fail-on-skip`, which fails the run on *any*
    SKIPPED result. Tests that are not ready to run on master live in
    [pvtest-list.md](pvtest-list.md), not as skipped dirs in the tree.
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
13. **Author for any target, not just appengine.** The script runs in the tester while
    `pvcontrol`/`pvcurl`/`pventer` may execute on a real device. Full rationale and the
    expected SKIP/FAIL classes on real devices: [devices.md](devices.md).

Always source `utils` at the top (`source /usr/share/pantavisor/pvtest/utils`); it provides
`pvcontrol`/`pventer`/`pvcurl`, `pv_exec`, the `wait_for_*` helpers, `pvr_clone_local_or_die`
and `pvr_post_rev`. After a reboot or a `pv_crash`, fence the come-back with `wait_for_down`
followed by `wait_for_target_ready`, passing a short label (`"after crash 2"`) whenever a test
fences more than once — otherwise each fence logs the same lines and the log cannot say which
one stalled.

**4. Generate the `output` file** (never edit manually):

```bash
./test.docker.sh -v run $SCOPE/$CATEGORY/$NAME -o
```

**5. Copy `output` back** to the source tree:

```bash
cp <workdir>/$SCOPE/$CATEGORY/$NAME/output \
   recipes-pv/pantavisor-pvtests/files/data/$SCOPE/$CATEGORY/$NAME/output
```

**6. Rebuild and verify** — see [index.md](index.md#build) for the full cleansstate command,
then re-run the test. Iterate between steps 4–6 until it passes cleanly.

**7.** Mark the test in [pvtest-list.md](pvtest-list.md) and in `TODO.md`.

## Updating expected output for an existing test

After a behaviour change makes an existing test fail with a known-good diff, regenerate its
`output`:

```bash
./test.docker.sh -v run local/core/legacy-config-overload -o
cp <workdir>/local/core/legacy-config-overload/output \
   recipes-pv/pantavisor-pvtests/files/data/local/core/legacy-config-overload/output
```

Then rebuild and verify as above.

## Adding a new container for a test

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

**3. Reference in `test.json`** by its deploy name. The path is relative to the scope root and
never names a target: `test.docker.sh` mounts the active target's
[`targets/<type>/<scope>/`](devices.md#per-target-container-tarballs) over
`/work/<scope>/common/tarballs`, so one reference resolves to the right architecture on every
board. The `.pvrexport.tgz` suffix comes from `container-pvrexport.bbclass` and is what every
MACHINE emits, which is what makes a board build's deploy dir a drop-in source:
```json
"tarballs": [
  "../../common/tarballs/<name>.pvrexport.tgz"
]
```

**4.** Rebuild.

## CI

Three workflows under `.github/workflows/` drive the suite; all run the tests job on the
self-hosted `pvtest-runner` label, which has docker, loop devices and the `sudo -n`
allowances listed in [index.md](index.md#first-time-system-setup).

| Workflow | Trigger | What it runs |
|---|---|---|
| `call-pvtests.yaml` | reusable (`workflow_call`) | The actual run. Inputs: `commit`, `test_path`, `parallel` (default `6`), `model` (default `volatile`; `all` expands to a `["volatile","persistent"]` matrix). Downloads the distro artifact, `CI_MODE=true ./test.docker.sh install-docker`, then runs with `-V --fail-on-skip`. Remote scope always runs serial (no `-p`). Uploads the workspace as `pvtest-workspace-<sha7>-<test_path>-<model>`. |
| `manual-pvtests.yaml` | `workflow_dispatch` | Builds `pantavisor-appengine-distro` for `docker-x86_64`, then calls `call-pvtests.yaml` with the four inputs forwarded. |
| `schedule-pvtests.yaml` | nightly cron (02:00) + dispatch | Same build, then `parallel: 6`, `model: all` — the nightly covers both assignment models. |

`onpush-scarthgap.yaml` also calls the reusable workflow with `test_path: local`,
`parallel: 6`, `model: volatile`, gated on non-draft PRs. Note that the build/test matrix is
gated `if: needs.check-draft.outputs.is_draft != 'true'`, so **CI does not run on drafts** —
promote with `gh pr ready` to get real feedback.

Workspaces are model-scoped so the two matrix legs don't collide. A cleanup step removes all
`pantavisor-appengine*` containers and images and both workspaces after each run.

There is no `--devices` path in CI yet; real-device runs are driven by hand.
