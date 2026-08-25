---
sidebar_position: 3
---
# Running pvtests Against a Real Device

The same suite that runs against the appengine pool runs against real hardware. The tester is
always x86, always runs on the host, and reaches the device over SSH and the pvr HTTP endpoint.
Only the example container tarballs the tests deploy are board-specific: they carry a rootfs
built for one architecture and signed by one CA.

For the framework itself see [index.md](index.md); for authoring tests and CI,
[appengine.md](appengine.md).

:::tip Quick reference: colibri-imx6ull end to end
colibri-imx6ull is the only board with a ready-made `build-targets/tests/` fragment today;
more targets will be added there over time. The steps below are the general pattern —
substitute another board's release config and manifest once it has one.

1. Flash the board's own BSP if it isn't already running Pantavisor:
   `kas build kas/build-configs/release/colibri-imx6ull-scarthgap.yaml`, then run the
   resulting `pv-flash-bundle-colibri-imx6ull-latest.tar.gz`'s `flash.sh`.
2. Extract the tester tarball and load its Docker images per its own `README.md` (unchanged
   from an appengine run — the tester is always x86 and runs on the host).
3. Build the example containers for this board:
   `kas build kas/build-configs/build-targets/tests/colibri-imx6ull.yaml`.
4. Install them as a target:
   `./test.docker.sh install-tarballs colibri-imx6ull build/tmp-scarthgap/deploy/images/colibri-imx6ull`.
5. Copy `device.txt` to `~/.config/pvtest/devices/colibri-imx6ull.txt`, fill in `name=`,
   `ip=`, `exec=`, `tty=`; set `type=colibri-imx6ull` if `name=` differs.
6. Run: `./test.docker.sh run local --device colibri-imx6ull`.

Every step is detailed below; `kas/build-configs/build-targets/tests/` gives step 3 as one
command for boards that have a fragment there — add one for another board the same way, or
fall back to the ad-hoc `kas shell … bitbake …` form under
[Building target tarballs](#building-target-tarballs) if it doesn't yet.
:::

## Setup

### Install

Extract the tarball and load the Docker images as described in the tarball's own `README.md`.

### The device manifest

`device.txt` is a template: copy it, fill it in, uncomment.

| Key | Required | Default | Meaning |
|---|---|---|---|
| `name=` | yes | — | identifies this one runner, console capture lands in `<name>.log` |
| `type=` | no | `name=` | the *class* of target, shared by every board of the same kind (the Yocto MACHINE is the natural value). This is what a test's `"devices"` allow-list matches |
| `ip=` | yes | — | device IP for the pvr HTTP endpoint on `:12368` → `PVTEST_HOST` |
| `exec=` | yes | — | command prefix to run `pvcontrol`/`pventer` on the device → `PVTEST_EXEC` |
| `tty=` | yes | — | host-local serial device path for console capture. Prefer a stable `/dev/serial/by-id/…` over `/dev/ttyUSBN` |
| `baud=` | no | `115200` | `stty` baud for the console |
| `hook=` | no | — | host command that sets the device's boot env and power-cycles it. When set, a test whose `config.env` doesn't match the live device re-types through this hook instead of SKIPping |
| `config=` | no | — | config file passed to `hook=` as `-c <file>` |
| `env=` | no | — | this board's base boot env, space-separated `KEY=VALUE`, passed to `hook=` ahead of each test's own tokens. Useful, for example, to set `PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct` so every test captures pantavisor's logs on the console |

Unrecognized keys produce a `WARN` and are ignored.

A manifest describes a *workstation's* board, so it lives in the host's pvtest config dir
rather than in a workspace the next install throws away:

```
~/.config/pvtest/
  rock5a.conf             <- whatever hook=/config= reads. Host-side only
  devices/                <- the only directory bind-mounted into the tester
    rock5a.txt            <- a named manifest, used by --device rock5a
    id_board              <- the SSH key exec= names, 0600
```

`--device` always takes a value and resolves it against that tree, name first:

| Invocation | Manifest |
|---|---|
| `--device rock5a` | `~/.config/pvtest/devices/rock5a.txt` |
| `--device ./b.txt`, `--device /abs/b.txt` | that path, when the config dir holds no such name |

**An installed manifest never implies device mode.** `--device` is the only thing that
selects a board: a run without it drives the appengine pool, whatever sits in the config dir.

### The re-type hook

A board is a slot like any other: the tester asks the host to bring slot 0 up on a given config
over the same ctrl protocol the appengine pool uses, and the host satisfies it by running this
board's hook (`PVTEST_RETYPE=hook`) instead of booting a container.

A hook is invoked as `hook [-c <config=>] KEY=VALUE ...`, with the manifest's `env=` tokens
prepended to the test's own (the test wins on any key both set). `env=` exists because a hook
typically writes the boot env as a full replacement. Leave it empty for a hook that merges.

A board with no `hook=` answers `unsupported`, which is a normal reply rather than an error:
the tester binds the board as it is and SKIPs any test whose `config.env` it doesn't
already satisfy — so run device-mode suites **without** `--fail-on-skip` until each test's
`"devices"` array is triaged.

Path rules: `hook=`/`config=` are consumed host-side only and may point anywhere on the host.
Paths in `exec=` must be absolute and inside the manifest's own directory — that directory is
bind-mounted into the tester at the same absolute path, so an SSH key anywhere else is
invisible to it.

### Building target tarballs

The example containers are ordinary `image` + `container-pvrexport` recipes with no arch
literals, so building *just those recipes* for the board's MACHINE is enough — any build
config with the right MACHINE and the right signing CA will do. `kas/build-configs/build-targets/tests/`
holds a per-board kas fragment that includes the board's release config and overrides
`target:` to just the `PV_PVTEST_CONTAINERS` set, so the build is one command:

```bash
kas build kas/build-configs/build-targets/tests/colibri-imx6ull.yaml
```

For a board without a fragment there yet, build the recipes directly against its release
config instead:

```bash
kas shell kas/build-configs/release/rpi-scarthgap.yaml -c \
    'bitbake pv-example-app pv-example-norole pv-example-ready \
             pv-example-ready-timeout pv-example-mgmt'
```

The exports land in the deploy dir under exactly the names the tests reference, making it a
drop-in source with no renaming or staging step:

```
build/tmp-scarthgap/deploy/images/raspberrypi/pv-example-app.pvrexport.tgz
```

- **Which containers.** `PV_PVTEST_CONTAINERS` in `pantavisor-appengine-distro.bb` is the
  authoritative list of what the suites consume. The `PV_PVTEST_CONTAINERS_XCONNECT` set
  (dbus/avahi) is pinned `"devices": ["appengine"]`, so a real-device run never needs it.
- **Architecture.** Each `pv-example-*.pvrexport.tgz` embeds a squashfs of a Yocto rootfs built
  for the current MACHINE/TUNE, so its busybox and coreutils will not run on another
  architecture. Nothing else in them is arch-bound.
- **Signature.** Each tarball carries a `_sigs/<PN>.json` `pvs@2` JWS produced by `pvr sig add`
  using the CA that `pvr-ca.bbclass` fetched; a device only accepts it if its BSP trust store
  holds the same CA. To switch vendor, set `PVS_VENDOR_NAME`, `PVS_URI` and `PVS_URI_SHA256`
  consistently across `container-pvrexport`, `pvrexport`, `pvroot-image` and `pantavisor-bsp`.
- **pvtx on the device.** `setup_test` installs each test's revision with `pvtx` when the
  device rootfs has it, falling back to a tester-side `pvr post`. On a low-spec board the
  `pvtx` path is a single fast transaction and worth having; add `pantavisor-pvtx` to the
  BSP's initramfs in the test distro conf if it isn't there.

### Installing target tarballs

```bash
./test.docker.sh install-tarballs radxa-rock5a <dir|tarball>...   # creates the tree
```

The target is the first argument and is required — it is deliberately not defaulted to
`appengine`. A target tree that does not exist yet is created on first install. Each install
prints what it wrote with a sha256 prefix per tarball, and installing for one board cannot
disturb another's or the shipped appengine set.

Only the tarballs vary by target, so the suites are **not** copied per board — `local/` and
`remote/` stay single shared trees:

```
<distro-root>/
  local/  remote/                        shared suites, one copy
    common/templates/                    scope-varying, target-invariant
  targets/
    appengine/{local,remote}/*.pvrexport.tgz
    radxa-rock5a/{local,remote}/*.pvrexport.tgz
```

At tester start, `test.docker.sh` bind-mounts `targets/<type>/<scope>/` over
`/work/<scope>/common/tarballs`, so a `test.json`'s relative
`../../common/tarballs/<name>.pvrexport.tgz` resolves to the right architecture on every
target and nothing in the test data mentions a target. `<type>` is the manifest's `type=`
field, or `appengine` for a run without `--device`, and `PVTEST_DEVICE_TYPE` overrides both.
Every run announces it at `INFO` in the head of `run.log`:

```
[ci-runner] 1753600000 INFO -- [test.docker.sh]: target type: radxa-rock5a (tarballs from targets/radxa-rock5a)
```

If the resolved target has no tree under `targets/`, the run **aborts before any container
starts**, listing the targets that do exist. A tree that exists but is missing a tarball a test
asks for fails later, in the runner, naming the tarball and the test that wanted it.

Name the tarball files explicitly, or stage them into a directory of their own and pass that:
pointing `install-tarballs` at a raw deploy directory also sweeps up
`pantavisor-bsp-*.pvrexport.tgz`, `pv-pvr-sdk-*.pvrexport.tgz` and versioned duplicates, which
the suites do not want. Target trees live in the *extracted* distro, not in the meta-pantavisor
source tree — a rebuild re-stages the pristine `targets/appengine/`.

## Running

```bash
./test.docker.sh run local --device rock5a
```

`./test.docker.sh -h` and the tarball `README.md` cover the rest. Device specifics:
`--device` is incompatible with `-p>1`, `-n` and `-V`, and forces `--model persistent`. `-i`
opens the tester console wired to the board; `-m` opens a shell on the board itself through
`exec=`, entering it as it is (no re-type, so the test's `config.env` is not applied) and
leaving it running on exit.

## Debugging

The run workspace's own `README.md` documents the layout, the log format and its sources, the
useful greps and the result lines. Two deltas against an appengine run:

- there is no `storage/` tree — the device keeps its own on-device storage;
- pantavisor's own log sources reach `test.log` only if the manifest sets
  `env=PV_LOG_SERVER_OUTPUTS=filetree,stdout_direct`. The serial console capture always lands
  in `<name>.log`.

### Expected outcomes

Not every non-PASS is a bug. Triage device results against these classes first:

- **SKIPPED because the test is pinned to another target is by design.** A test whose
  `"devices"` allow-list excludes this target never runs here (see the target-pinning rule
  in [appengine.md](appengine.md#test-authoring-rules)); the log line names the target and
  the list. Today that is `local/core/*-config-overload` (their golden output asserts
  appengine-specific config values, and `PV_POLICY=test` requires a `test.config` policy a
  BSP need not ship — a missing policy file is fatal to pantavisor init), `local/xconnect/*`
  (they need the `xconnect-dbus-systembus` build feature and its example containers), and
  `local/services/daemons` (it asserts the appengine image's daemon set).
- **SKIPPED on unmet `config.env` with no `hook=` configured is by design, not a failure.**
  Without a hook a real device's config is immutable per test, so e.g. the
  config-overload tests (`PV_POLICY=test`), the secureboot tests (`PV_SECUREBOOT_MODE=strict`)
  and `on-demand-gc` (`PV_STORAGE_LOGTEMPSIZE=` — persistent logs) skip wherever the device's
  live config says otherwise. Never change a device's config or BSP just to un-skip a test —
  configure a `hook=` instead if the device supports boot-time config injection.
- **Timeouts**: device runs default `PVTEST_TEST_TIMEOUT` to 1800 s (vs 600 s for
  containers) — updates may need real reboots and every forwarded poll pays an ssh
  round-trip.
