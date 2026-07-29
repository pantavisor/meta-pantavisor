---
sidebar_position: 3
---
# Running pvtests Against a Real Device

The same suite that runs against the appengine pool runs against real hardware. Nothing about
the tester is board-specific: it is always x86, always runs on the host, and reaches the
device over SSH and the pvr HTTP endpoint — the two channels a pantavisor device exposes
anyway. What *is* board-specific is the set of example container tarballs the tests deploy,
because those carry a rootfs built for one architecture and signed by one CA.

So the flow is:

1. install the stock **x86** appengine distro — its tester container works against any target,
2. fill in a `devices.txt` manifest describing the board,
3. install container tarballs built for that board, if its architecture or signing CA
   differs — they go in their own `targets/<type>/` tree, leaving the suites untouched,
4. run.

```bash
./test.docker.sh install-docker                       # 1
cp devices.txt my-device.txt && $EDITOR my-device.txt # 2
./test.docker.sh install-tarballs smm-m2 ../m2-tarballs/     # 3
PH_USER=... PH_PASS=... ./test.docker.sh run local --devices my-device.txt   # 4
```

No vendor-layer change upstream is required for any of this.

## The device manifest

`devices.txt` is a template: copy it, fill it in, uncomment. Stanzas are separated by blank
lines, one per board; the runner currently accepts exactly one device per run.

| Key | Required | Default | Meaning |
|---|---|---|---|
| `name=` | yes | — | identifies this one runner: console capture lands in `<name>.log`, and it is the lock key. → `PVTEST_DEVICE_NAME` |
| `type=` | no | `name=` | the *class* of target, shared by every board of the same kind (the Yocto MACHINE is the natural value). This is what a test's `"devices"` allow-list matches. → `PVTEST_DEVICE_TYPE` |
| `ip=` | yes | — | device IP for the pvr HTTP endpoint on `:12368` → `PVTEST_HOST` |
| `exec=` | yes | — | command prefix to run `pvcontrol`/`pventer` on the device → `PVTEST_EXEC` |
| `tty=` | yes | — | host-local serial device path for console capture. Prefer a stable `/dev/serial/by-id/…` over `/dev/ttyUSBN` |
| `baud=` | no | `115200` | `stty` baud for the console |
| `hook=` | no | — | host command that sets the device's boot env and power-cycles it. When set, a test whose `config.env` doesn't match the live device re-types through this hook instead of SKIPping |
| `config=` | no | — | config file passed to `hook=` as `-c <file>` |
| `env=` | no | — | this board's base boot env, space-separated `KEY=VALUE`, passed to `hook=` ahead of each test's own tokens |

`exec=` ssh commands **must** carry
`-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=3 -o ServerAliveCountMax=2`:
reboot-class updates black-hole established TCP connections, and an ssh without keepalives
blocks on them forever.

Unrecognized keys produce a `WARN` and are ignored. `--devices` is incompatible with `-p>1`,
`-m`, `-n` and `-V`, and forces `--model persistent`.

### The re-type hook

A board is a slot like any other. The tester asks the host to bring slot 0 up on a given
config over the same ctrl protocol the appengine pool uses; the only difference is what the
host does to satisfy that request — boot a new container generation (`PVTEST_RETYPE=container`)
or run this board's hook (`PVTEST_RETYPE=hook`). A board with no `hook=` answers `unsupported`,
which is a normal reply rather than an error: the tester binds the board as it is and SKIPs
any test whose `config.env` it doesn't already satisfy.

A hook is invoked as `hook [-c <config=>] KEY=VALUE ...`, and typically writes the boot env as
a full replacement — so passing only a test's own `config.env` would drop everything else the
device needs to stay usable. That is what the manifest's `env=` field is for: the host prepends
those board-level tokens to the test's own on every re-type, so the test still wins on any key
both set, and a board that boots with, say, a fixed log or secure-boot setting keeps it across
re-types. Leave `env=` empty for a hook that merges rather than replaces. This happens entirely
host-side — the tester only ever sends a test's own required config.

Without `hook=`, tests whose `config.env` the live device doesn't already satisfy are SKIPPED
instead of power-cycled — so run device-mode suites **without** `--fail-on-skip` until each
test's `"devices"` array is triaged.

Since `hook=`/`config=` are consumed host-side only (never bind-mounted into the tester), they
may point anywhere on the host. Paths in `exec=`, by contrast, must be absolute and inside the
manifest's own directory: `test.docker.sh` bind-mounts that directory into the tester at the
same absolute path and evaluates `exec=` there, so an SSH key anywhere else is invisible to the
tester.

## Per-target container tarballs

The suites ship with the example containers built for the appengine — an x86 rootfs signed by
the build's `PVS_VENDOR_NAME` CA. A board of another architecture cannot run those binaries,
and a board that trusts a different CA will reject their signatures.

Only the tarballs vary by target, so the suites are **not** copied per board. `local/` and
`remote/` stay single shared trees, and each target's containers live in their own tree:

```
<distro-root>/
  local/  remote/                        shared suites, one copy
    common/templates/                    scope-varying, target-invariant
  targets/
    appengine/{local,remote}/*.pvrexport.tgz
    smm-m2/{local,remote}/*.pvrexport.tgz
```

At tester start, `test.docker.sh` bind-mounts `targets/<type>/<scope>/` over
`/work/<scope>/common/tarballs`. The tester therefore always sees the same path whichever
target supplied the bytes, which is what keeps every `test.json`'s relative
`../../common/tarballs/<name>.pvrexport.tgz` — and the handful of absolute
`/work/local/common/tarballs/...` references inside test scripts — target-agnostic. Nothing in
the test data mentions a target.

`<type>` is the manifest's `type=` field, or `appengine` for a run without `--devices`, and
`PVTEST_DEVICE_TYPE` overrides both. Every run announces it at `INFO` in the head of `run.log`:

```
[ci-runner] 1753600000 INFO -- [test.docker.sh]: target type: smm-m2 (tarballs from targets/smm-m2)
```

If the resolved target has no tree, the run **aborts before any container starts**, listing the
targets that do exist — a board whose tarballs were never installed fails loudly instead of
silently testing x86 binaries against arm hardware.

### Installing a target's tarballs

```bash
./test.docker.sh install-tarballs smm-m2 <dir|tarball>...   # install (creates the tree)
./test.docker.sh install-tarballs smm-m2 --list             # what is installed
./test.docker.sh install-tarballs smm-m2 --reset            # restore/remove
./test.docker.sh install-tarballs smm-m2 -s remote <dir>    # one scope only
```

The target is the first argument and is required — it is deliberately not defaulted to
`appengine`, since a forgotten argument would then drop a board's tarballs into the pool's
tree. A target tree that does not exist yet is created on first install, so introducing a board
needs no separate setup step. `PVTEST_TARBALLS_PATH` supplies a default source. Each target
keeps its own append-only `pvtest-tarballs.manifest` inside its tree — epoch, scope, name,
action, sha256 prefix and source path — so `--list`/`--reset` never mix two boards' records,
and installing for one board cannot disturb another's or the shipped appengine set.

Target trees live in the *extracted* distro, not in the meta-pantavisor source tree — a rebuild
re-stages the pristine `targets/appengine/`.

### Producing replacement tarballs

The example containers are ordinary `image` + `container-pvrexport` recipes with no arch
literals, so building *just those recipes* for the board's MACHINE is enough. You do **not**
need a whole `pantavisor-appengine-distro` for that MACHINE — any build config that gives you
the right MACHINE and the right signing CA will do. With a Raspberry Pi as the worked example:

```bash
kas shell kas/build-configs/release/rpi-scarthgap.yaml -c \
    'bitbake pv-example-app pv-example-norole pv-example-ready \
             pv-example-ready-timeout pv-example-mgmt'
```

The exports land in the deploy dir under exactly the names the tests reference — the
`.pvrexport.tgz` suffix comes from `container-pvrexport.bbclass`, so it is the same for every
MACHINE:

```
build/tmp-scarthgap/deploy/images/raspberrypi/pv-example-app.pvrexport.tgz
```

That makes the deploy dir a drop-in source, with no renaming or staging step:

```bash
cd <extracted-distro>
./test.docker.sh install-tarballs raspberrypi \
    <build>/tmp-scarthgap/deploy/images/raspberrypi/pv-example-app.pvrexport.tgz \
    <build>/tmp-scarthgap/deploy/images/raspberrypi/pv-example-norole.pvrexport.tgz
```

Pass the target name matching the `type=` you put in `devices.txt` — that is the whole binding
between a board and its containers. Name the files explicitly, or stage them into a directory
of their own and pass that: pointing `install-tarballs` at a raw deploy directory also sweeps
up `pantavisor-bsp-*.pvrexport.tgz`, `pv-pvr-sdk-*.pvrexport.tgz` and versioned duplicates,
which the suites do not want.

`PV_PVTEST_CONTAINERS` in `pantavisor-appengine-distro.bb` is the authoritative list of what
the suites consume. The `PV_PVTEST_CONTAINERS_XCONNECT` set (dbus/avahi) is built only when
`PANTAVISOR_FEATURES` carries `xconnect-dbus-systembus`, and the two tests that use it are
pinned `"devices": ["appengine"]` — so a real-device run never needs those.

Building the full `pantavisor-appengine-distro` for the board's MACHINE is still an option if
you want a board-native workspace rather than one distro serving every target. Set
`PV_APPENGINE_CONTAINERS = ""` and `PVTEST_TARGET_TYPE = "<type>"` in that distro conf: the x86
appengine/netsim/tester docker images cannot be cross-built from an arm MACHINE (and
multiconfig can't do it in-tree), and no container is booted against a real device anyway. You
then have to bundle a host-side x86 tester image from a separate build, which is why installing
into one distro's `targets/` is usually the cheaper path.

**Architecture.** Each `pv-example-*.pvrexport.tgz` embeds a squashfs of a Yocto rootfs built for the
current MACHINE/TUNE (`pvr app add --type rootfs --from ${IMAGE_ROOTFS}`), so its busybox and
coreutils will not run on another architecture. Nothing else in them is arch-bound.

**Signature.** Each tarball carries a `_sigs/<PN>.json` `pvs@2` JWS produced by
`pvr sig add` using the CA that `pvr-ca.bbclass` fetched. A device only accepts them if its
BSP trust store contains the same CA — which the `PV_SECUREBOOT_MODE=strict` tests exercise
directly. To switch vendor, set `PVS_VENDOR_NAME`, `PVS_URI` and `PVS_URI_SHA256` consistently
across `container-pvrexport`, `pvrexport`, `pvroot-image` and `pantavisor-bsp`. The two
checked-in `pv-oem-developer-001*.pvrexport.tgz` fragments are config-only (no rootfs), so they need no
change for a different architecture, but would have to be re-signed by hand for a different
signing vendor — they exist for `local/security/oem-secureboot`, which is pinned to
`appengine` anyway.

**pvtx on the device.** `setup_test` installs each test's revision with `pvtx` when the device
rootfs has it, falling back to a tester-side `pvr post`. On a low-spec board the `pvtx` path is
a single fast transaction and worth having; add `pantavisor-pvtx` to the BSP's initramfs in the
test distro conf if it isn't there. Because `pantavisor-pvtx` builds from the same recipe and
SRCREV as the runtime, the on-device `pvtx` and pantavisor versions always agree.

## Which tests run where

Each `test.json` may carry a `"devices"` array — an allow-list of the target *classes* the test
is restricted to. Absent or empty means "run everywhere", the default for almost every test.
Use it for tests that *cannot* pass elsewhere: ones whose golden output asserts the appengine
baseline, or that need a pantavisor build feature a given BSP doesn't ship.

An entry matches `PVTEST_DEVICE_TYPE`: `appengine` for a container, the manifest's `type=` for
a real device. The class, not the runner — a pin holds for every board of that kind, so a
second board of the same model needs no test change. `PVTEST_DEVICE_NAME` identifies the
individual runner and is never matched here.

```
"devices": ["appengine"]                # container only — e.g. asserts the appengine baseline
"devices": ["appengine", "<machine>"]   # also on every board of that machine class
```

## Expected outcomes on real devices

Not every non-PASS is a bug. Triage device results against these classes first:

- **SKIPPED because the test is pinned to another target is the design.** A test whose
  `"devices"` allow-list excludes this target never runs here; the log line names the target
  and the list. Today that is `local/core/*-config-overload` (their golden output asserts
  appengine-specific config values, and `PV_POLICY=test` requires a `test.config` policy a BSP
  need not ship — a missing policy file is fatal to pantavisor init), `local/xconnect/*` (they
  need the `xconnect-dbus-systembus` build feature and its example containers), and
  `local/services/daemons` (it asserts the appengine image's daemon set, which follows from
  that image's `PANTAVISOR_FEATURES` and differs on any real BSP).
- **SKIPPED on unmet `config.env`, when no `hook=` is configured, is the design, not a
  failure.** Without a hook a real device's config is immutable per test, so e.g. the
  config-overload tests (`PV_POLICY=test`), the secureboot tests (`PV_SECUREBOOT_MODE=strict`)
  and `on-demand-gc` (`PV_STORAGE_LOGTEMPSIZE=` — persistent logs; a device that keeps logs on
  tmpfs legitimately loses them across its real reboots, independent of any hook) skip wherever
  the device's live config says otherwise. Never change a device's config or BSP just to
  un-skip a test — configure a `hook=` instead if the device supports boot-time config
  injection.
- **FAILED can be expected when the device BSP ships an older or foreign pantavisor** than the
  tests were authored against: CLI output skew (e.g. an old `pvcontrol` printing HTTP response
  headers) or a different built-in daemon set (e.g. no `pv-xconnect`) fail the diff, and that
  is acceptable — the golden outputs track the pantavisor under test, not every BSP in the
  field.
- **Timeouts**: device runs default `PVTEST_TEST_TIMEOUT` to 1800 s (vs 600 s for containers) —
  updates may need real reboots and every forwarded poll pays an ssh round-trip.

## Authoring for cross-target portability

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
  never a literal listing (see `local/security/object-checksum`), or filter to content the test
  itself installs (see `local/security/container-roles`).
