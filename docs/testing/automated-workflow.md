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

Logs land in `./test.docker.log`. Pantavisor storage is preserved at `<tmpdir>/storage/<scope>/<category>/<name>/` for post-run inspection.

## Interpreting test results

With `-v`, the run ends with a summary block:

```
=======================================================
======================= SUMMARY =======================
=======================================================
Info: workspace=/tmp/pv_appengine.jBZqVz
Info: logs=/tmp/pv_appengine.jBZqVz/test.docker.log
Info: valgrind results=/tmp/pv_appengine.jBZqVz/valgrind
Info: Pantavisor storage=/tmp/pv_appengine.jBZqVz/storage

Info: 'local/core/legacy-config-overload' PASSED (23 s)
Info: 'local/lifecycle/reboot-nonreboot-rollback' FAILED (110 s)
Info: 'local/runtime/remount-policies' SKIPPED
=======================================================
```

Each test runs a script (`resources/test`) and diffs its stdout against the stored `output` file. A failure means the actual output diverged from the expected output. The diff is embedded in the framework log (see below).

### Framework log

`<workspace>/test.docker.log` contains the full bash-traced output of `test.docker.sh`. To find what went wrong for a specific failing test, search for its diff block:

```bash
grep -A40 "--- /dev/fd" /tmp/pv_appengine.<id>/test.docker.log
```

Lines prefixed with `-` are what was expected; lines prefixed with `+` are what the test produced.

### Storage

The workspace keeps the full Pantavisor storage directory for every test that ran, under `<workspace>/storage/<scope>/<category>/<name>/`. This mirrors the on-device storage layout and is the primary place to inspect what the runtime actually did.

```
<workspace>/storage/<scope>/<category>/<name>/
  trails/         <- revision snapshots (objects, configs, per-container dirs)
  objects/        <- content-addressed object store
  disks/          <- persistent disk images
  dm-crypt-files/ <- dm-crypt key material
  cache/
  boot/
  config/
  logs/           <- see below
```

#### Logs

```
logs/
  current/              <- live log snapshot at test end
    pantavisor/
      pantavisor.log    <- main Pantavisor log
    <container>/
      lxc/
        lxc.log         <- LXC internals
        console.log     <- container console output
      var/log/
        messages        <- syslog inside the container
  0/                    <- rotated snapshot (first boot cycle)
  locals/               <- per-local-revision log snapshots
    <local-name>/
      pantavisor/
        pantavisor.log
```

The main log to check first is always `logs/current/pantavisor/pantavisor.log`. For tests that exercise local revisions, each revision also has its own snapshot under `logs/locals/<local-name>/`.

Useful greps:

```bash
# Show only errors and warnings
grep " ERROR\b\| WARN\b" logs/current/pantavisor/pantavisor.log

# Exclude noisy disk-crypt stderr (routed through the WARN channel)
grep " WARN\b" pantavisor.log | grep -v "\[disk-crypt-err\]"
```

Expected recurring WARNs that are normal in the appengine environment:

| Source | Message | Reason |
|--------|---------|--------|
| `[ipam]` | `failed to enable IP forwarding` | No network namespace in appengine |
| `[pv-xconnect-err]` | `Error connecting to pv-ctrl: Connection reset by peer` | Normal on shutdown |
| `[platforms]` | `sent SIGKILL to logger '...'` | Loggers that don't self-exit on teardown |
| `[network]` | `unable to create bridge dev lxcbr0: File exists` | Bridge already exists from prior test |

### Valgrind results

With `-V`, each process gets its own `valgrind.log.<pid>` file under `<workspace>/valgrind/<group>/<num>/`. Pantavisor forks heavily via LXC, so there will be many files. The main Pantavisor worker is typically the largest:

```bash
ls -S /tmp/pv_appengine.<id>/valgrind/local/lifecycle/reboot-nonreboot-rollback/ | head -3
```

Each file ends with a LEAK SUMMARY and ERROR SUMMARY:

```bash
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
| `setup.cmdline` | kernel cmdline overrides | `""` if not needed |
| `setup.env` | space-separated `KEY=VALUE` env vars for Pantavisor | e.g. `"PV_WDT_MODE=disabled PV_SECUREBOOT_MODE=disabled"` |
| `setup.pantavisor.config` | path to a custom `pantavisor.config`, or `""` | e.g. `"resources/pantavisor.config"` |
| `setup.pvs` | glob for PVS signing key tarballs | keep `"../../common/pvs/*.tar.gz"` for local; `""` for remote |
| `setup.containers.control` | name of the container used as control plane | usually `"pvr-sdk"` |
| `setup.containers.tarballs` | list of container pvrexport tarballs | always include `bsp.tgz` and `pvr-sdk.tgz`; add extra containers as needed |
| `setup.containers.urls` | OTA container URLs (remote tests) | `[]` for local tests |
| `setup.ready-script` | script to run once Pantavisor reaches READY | `""` if not needed; `"resources/ready"` otherwise |
| `setup.self-claim` | remote tests only: auto-claim the device | `"true"` |
| `test-script` | path to the test script | `"resources/test"` |
| `skip` | exclude test from runs | `"false"` normally; `"true"` to disable |

**3. Write `resources/test`:**

```sh
#!/bin/sh

source /work/scripts/utils
. /opt/pantavisor/set_env

# Use pventer to run commands inside a container; stdout is diff-ed against `output`
pventer -c pvr-sdk pvcontrol config ls | jq -M -r '.["policy"]'
```

Guidelines (from `GEMINI.md` conventions):
- Always source `utils` and `set_env` at the top — they set up the test environment
- Use `pventer -c <container> <cmd>` for commands inside containers
- Use `pvcontrol` and `pvcurl` for the pv-ctrl API
- **Output determinism**: pipe JSON through `jq -M` (compact, sorted) and use `tr -d '\r'` to strip carriage returns — the runner diffs stdout byte-for-byte
- Keep tests independent: each test starts from a clean container and storage state

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
| `-i`, `--interactive` | Open a shell once Pantavisor reaches READY (device claimed if configured). Use to inspect a working system. Requires a specific leaf test path. |
| `-m`, `--manual` | Open a shell without starting Pantavisor. Use when PV fails to reach READY and you need to debug startup. Requires a specific leaf test path. |
| `-o`, `--overwrite` | Create or overwrite the expected test output (use when authoring or updating tests) |
| `-n`, `--netsim` | Enable wireless network simulation via `mac80211_hwsim` (experimental) |

**Exit codes**: `0` = PASSED, `1` = FAILED, `2` = ABORTED

---

## Test plan

Tests are organized by scope (`local` / `remote`) and category. The table below tracks implementation status.

### local — tests running entirely within the appengine container

#### core
| Test | Description | Done |
|------|-------------|------|
| `local/core/legacy-config-overload` | Legacy configuration overload | ✓ |
| `local/core/modern-config-overload` | Modern configuration overload (Env/Cmdline) | ✓ |
| `local/core/invalid-config-values` | Invalid Configuration Values Handling | |
| `local/core/rootfs-namespace` | Rootfs namespace (mounts, symlinks, etc.) | |

#### lifecycle
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
| Test | Description | Done |
|------|-------------|------|
| `local/runtime/invalid-state-json` | Invalid State JSON | |
| `local/runtime/large-state-json` | Large State JSON (100+ containers) | |
| `local/runtime/container-groups-startup` | Container Groups and Startup Order | |
| `local/runtime/container-storage-persistence` | Container Storage Persistence | |
| `local/runtime/config-overlay` | Configuration Overlay | |
| `local/runtime/resource-constraints` | Resource Constraints (CPU/Mem) | |
| `local/runtime/status-goal-success-failure` | Status Goal Success and Failure | ✓ |
| `local/runtime/container-exports` | Container Exports to Host | ✓ |
| `local/runtime/remount-policies` | Remount Policies (PV_REMOUNT_POLICY) | ✓ |

#### control
| Test | Description | Done |
|------|-------------|------|
| `local/control/basic-endpoints` | Basic Endpoints (Containers, Objects, etc.) | ✓ |
| `local/control/invalid-signal-handling` | Invalid Signal Handling | |
| `local/control/local-run-command` | Local Run Command | |
| `local/control/ssh-override` | SSH Override | |
| `local/control/object-step-management` | Object & Step Management | |
| `local/control/metadata-manipulation` | Metadata Manipulation | |
| `local/control/pvcontrol-pvcurl` | pvcontrol & pvcurl tool verification | |

#### xconnect
| Test | Description | Done |
|------|-------------|------|
| `local/xconnect/unix-sockets` | Unix Sockets (UDS proxying) | |
| `local/xconnect/rest-over-uds` | REST-over-UDS (Identity headers) | |
| `local/xconnect/dbus` | D-Bus (Policy mediation) | |
| `local/xconnect/drm` | DRM (Graphics node injection) | |
| `local/xconnect/wayland` | Wayland (Isolated UI rendering) | |

#### security
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
| Test | Description | Done |
|------|-------------|------|
| `local/services/log-output-formats` | Log Output Formats (filetree/singlefile) | |
| `local/services/on-demand-gc` | On-Demand Garbage Collection | ✓ |
| `local/services/tsh-daemon` | tsh daemon management & log capture | |
| `local/services/log-rotation` | Log rotation functionality | |
| `local/services/ipam-single-pool` | Single IPAM pool — container gets IP from pool | |
| `local/services/ipam-multi-pool` | Two IPAM pools — correct address assignment | |
| `local/services/ipam-collision` | Conflicting pool addresses detected and rejected | |
| `local/services/ipam-invalid` | Invalid IPAM config rejected gracefully | |
| `local/services/ipam-lxcbr` | IPAM with lxcbr bridge networking | |

---

### remote — tests requiring Pantahub connectivity

#### core
| Test | Description | Done |
|------|-------------|------|
| `remote/core/encrypted-pantahub-config` | Encrypted `pantahub.config` handling | ✓ |
| `remote/core/unencrypted-pantahub-config` | Unencrypted `pantahub.config` handling | ✓ |

#### lifecycle
| Test | Description | Done |
|------|-------------|------|
| `remote/lifecycle/simultaneous-updates` | Successful Multiple Simultaneous Remote Updates | ✓ |
| `remote/lifecycle/insufficient-disk-space` | Update with Insufficient Disk Space | ✓ |
| `remote/lifecycle/rollback-cloud-status` | Trigger rollback and verify cloud status | ✓ |
| `remote/lifecycle/update-retries-pv-crash` | Update retries when PV crashes | ✓ |
| `remote/lifecycle/update-retries-gc-pressure` | Update retries when PV crashes with GC pressure | ✓ |
| `remote/lifecycle/claim-after-local-updates` | Claim after local updates with random artifacts | |

#### control
| Test | Description | Done |
|------|-------------|------|
| `remote/control/manual-claim` | Manual Device Claim | ✓ |
| `remote/control/auto-claim` | Automatic Device Claim | ✓ |
| `remote/control/always-remote-disabled` | Always Remote Disabled | |
| `remote/control/always-remote-enabled` | Always Remote Enabled | ✓ |
| `remote/control/device-user-metadata` | Device/User Metadata Exchange | |

#### services
| Test | Description | Done |
|------|-------------|------|
| `remote/services/ph-logger-cloud-push` | `ph-logger` cloud push | ✓ |

