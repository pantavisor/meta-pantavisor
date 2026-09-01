---
title: "Automated Testing"
sidebar_position: 1
---
# The pvtest Framework

pvtest is able to run a single suite of tests against two kinds of target:

- A **slot pool** of one to many **appengine** containers driven in parallel.
- A **real device** over the network.

Both targets share the same machinery: one **tester** container holding `-p` slots, each slot
holding one target. They differ only in how a slot's target is obtained and re-typed (rebooted
into the test-specific env), which is what [Execution Flow](#execution-flow) describes.

This page covers the framework itself, how it is built, how it is laid out, how to use it and
where its output lands. For running against appengine and authoring new tests see
[appengine.md](appengine.md). For running against real hardware see [device.md](device.md),
and for driving a device from a host with no container runtime, [native.md](native.md).
For a list of tests that are implemented and pending to do, see
[pvtest-list.md](pvtest-list.md).

## Architecture

The framework is split into three parts:

- A thin **`test.docker.sh`** in charge of orchestrating the necessary Docker containers from
  the host.
- A **`pantavisor-tester`** container that runs a flat test queue against the targets, be it
  **appengine** containers or a **real device**.
- Zero to many **`pantavisor-appengine`** containers that expose SSH and the pvr HTTP API
  exactly as a real device would. They run on the host too, and are interchangeable with a real
  device.

The tester drives each target over two channels:

- **`PVTEST_EXEC`**: a command prefix (typically `ssh …`) used to run `pvcontrol`/`pventer` on
  the target.
- **`PVTEST_HOST`**: the host IP for the target's pvr HTTP endpoint, used by `pvr`/`curl`.

The host also keeps a control channel open to the tester for the whole run, whatever the
target:

- **`PVTEST_CTRL`**: a file protocol the tester uses to ask the host for a target in a given
  config. Requests carry `slot=`, `cfg=`, `storage=`, `rev=` and `seed=`; replies carry
  `status=ready|down|failed|unsupported` plus `ae=` naming the target and `exec=`/`host=`
  saying how to reach it. What the host does with a request is decided by `PVTEST_RETYPE`,
  not by the kind of target.

### Topology

**Tester + appengine pool** — tester and appengines both on the HOST, all x86
```
 HOST (x86)
 ┌────────────────────────────────────────────────────────────────────────┐
 │  test.docker.sh   (slot pool: -p N slots, host re-types on demand)     │
 │                                                                        │
 │  ┌────────────────────┐         ┌──────────────────────────┐           │
 │  │  pantavisor-tester │──SSH───►│  pantavisor-appengine-0  │           │
 │  │   (x86, runner)    │ (EXEC)  │  ├─ pantavisor (PID1)    │           │
 │  │  pvtest-run        │──HTTP──►│  ├─ pvr-sdk (LXC)        │           │
 │  │  pvr  curl  jq     │ :12368  │  ├─ pvcontrol / pventer  │           │
 │  │  valgrind          │ (HOST)  │  └─ sshd                 │           │
 │  │                    │         └────────────┬─────────────┘           │
 │  │  N slots over a    │──SSH───►┌────────────┴─────────────┐           │
 │  │  global FIFO; each │──HTTP──►│  pantavisor-appengine-N  │  …        │
 │  │  slot re-types its │         └────────────┬─────────────┘           │
 │  │  container on      │                      │ docker logs -f          │
 │  │  demand            │                      ▼                         │
 │  └────────────────────┘              <container>.log  (on the host)    │
 └────────────────────────────────────────────────────────────────────────┘
```

**Tester + real device** — tester on the HOST (x86); the external device may be another arch
```
 HOST (x86 runner)                     external device (arm32/arm64, elsewhere)
 ┌────────────────────────────┐        ┌──────────────────────────┐
 │  test.docker.sh --device   │        │   arm32 / arm64 device   │
 │                            │  SSH   │  ├─ pantavisor (PID1)    │
 │  ┌────────────────────┐    │ (EXEC) │  ├─ pvr-sdk (LXC)        │
 │  │  pantavisor-tester │────┼───────►│  ├─ pvcontrol / pventer  │
 │  │   (x86, runner)    │────┼─HTTP──►│  └─ sshd                 │
 │  │  pvtest-run        │    │ :12368 └────────────┬─────────────┘
 │  │  pvr  curl  jq     │    │                     │ serial (tty)
 │  └─────────┬──────────┘    │◄────────────────────┘
 │            ▼               │
 │      <name>.log            │
 └────────────────────────────┘
```

### Where the Code Lives

The framework spans both repos: the in-container runner is built from pantavisor, everything
the host needs is built from this layer.

In **pantavisor**, under `pvtest/` (built when `PANTAVISOR_PVTEST=ON`):

| Path | Role | Ships as |
|---|---|---|
| `pvtest/pvtest-run.in` | the tester container entrypoint, runs the tests against the targets | `pantavisor-pvtest` package → `/usr/bin/pvtest-run` |
| `pvtest/utils.in` | library sourced by `pvtest-run` and by every test's `resources/test` | same package → `/usr/share/pantavisor/pvtest/utils` |
| `pvtest/common.in` | helpers shared by the runner *and* the host orchestrator | same package → `/usr/share/pantavisor/pvtest/common` |

In **meta-pantavisor**:

| Path | Role | Ships as |
|---|---|---|
| `recipes-pv/pantavisor/pantavisor-appengine-distro/test.docker.sh` | the host orchestrator, runs outside every container | deployed to the distro tarball root |
| `…/pantavisor-appengine-distro/device.txt` | device manifest template, can be installed in host at `~/.config/pvtest/devices/` | tarball root |
| `…/pantavisor-appengine-distro/common` | host copy of pantavisor's `pvtest/common.in`, kept byte-identical | tarball root, as `pvtest/common` |
| `…/pantavisor-appengine-distro/tarball-README.md` | quick reference for running the suite | tarball root, as `README.md` |
| `…/pantavisor-appengine-distro/workspace-README.md` | layout guide for a finished run's output | tarball root, copied into each run workspace as `README.md` |
| `recipes-pv/pantavisor-pvtests/files/local/`, `files/remote/` | the test suites | tarball root as `local/` and `remote/` |

`common` is the only file duplicated across the repos: the tester container gets it from the
`pantavisor-pvtest` package, the host from the tarball. Change one, change the other.

## Execution Flow

The tester container will drive the test execution in two different ways based on these storage
models:

- **`volatile`**: storage is new for every test.
- **`persistent`**: storage is persistent across test iterations.

A real device is not a separate code path: it is `-p 1` plus the persistent model plus
`setbootconfig`/`none` re-typing.

### Volatile Model

Only possible if targets are appengine containers. Not implemented for real devices to avoid
time costly flashing between iterations.

As containers are discarded after every test, we save a lot of time avoiding both setup to get
the target ready for the test and teardown to clean up after, so it is designed primarily to
get the fastest pipeline execution possible.

In this case, the initial revision and env config are seeded before boot, so the container
comes up already on the test's revision.

```
 ┌────────────────────────────┐
 │  Pick next test (queue)    │   alphabetical, per slot
 │  • stage tarballs to seed/ │
 └─────────────┬──────────────┘
               │ ctrl: cfg + storage=<test> + rev + seed
               ▼
 ┌────────────────────────────┐
 │  Boot a fresh appengine    │◄─────────────────────────────┐
 │  • test env cfg on the box │                              │
 │  • empty storage           │                              │
 │  • pvtx seeds initial rev  │                              │ more tests
 └─────────────┬──────────────┘                              │
               │ boots into the test's revision              │
               ▼                                             │
 ┌────────────────────────────┐                              │
 │  Bind + setup              │                              │
 │  • readiness fence         │                              │
 │  • assert rev + config     │                              │
 │  • gc, go-remote, claim    │                              │
 └─────────────┬──────────────┘                              │
               ▼                                             │
 ┌────────────────────────────┐                              │
 │  Run test  (exec_test)     │                              │
 │  • run resources/test      │                              │
 │  • diff vs golden output   │                              │
 └─────────────┬──────────────┘                              │
               ▼                                             │
 ┌────────────────────────────┐                              │
 │  Discard  (teardown)       │──────────────────────────────┘
 │  • delete device on Hub    │
 │  • poweroff, drop container│
 └────────────────────────────┘
```

There is no factory clone or export and no install step, which is where the time is saved.
Storage is keyed by test id rather than by slot, and the Hub device is deleted after every test
because the container will not survive to be reused.

This loop is repeated until the tester has executed all of the flat queue provided by the host
in alphabetical order.

### Persistent Model

Aimed at real devices with persistent storage between tests, but also compatible with
appengine, where we simulate the same behavior.

As storage will survive after each test, we need to be careful to provide each iteration with
the cleanest state possible (install and commit the initial revision, run garbage collector,
unclaim, claim or go remote when needed...), as well as writing the tests to be agnostic to the
device's prior state.

To achieve this, the host sets `PVTEST_RETYPE` to tell the tester how a target is re-typed into
the desired env config with the following possible values:

- `container`: for the appengine pool, which just runs a new container generation while keeping
  the persistent storage.
- `setbootconfig`: for real devices, which runs the manifest's `setbootconfig=` script to set
  the boot config and power-cycle the board.
- `none`: for real devices with no `setbootconfig=`. The tester binds the target as it is, and
  every test whose config the device does not already satisfy is SKIPPED.

```
 ┌────────────────────────────┐
 │  Init device(s)  (once)    │   per target, in parallel:
 │  • readiness fence         │   • collect device info
 │    (SSH..pvr endpoint)     │   • clone + export factory revision
 └─────────────┬──────────────┘
               │ pool ready
               ▼
 ┌────────────────────────────┐
 │  Install initial revision  │◄─────────────────────────────┐
 │  (setup_test)              │                              │
 │  • install locals/<test>   │                              │
 │    (pvtx; pvr fallback)    │                              │ more tests
 │  • ONE power cycle:        │                              │
 │    re-type (config change) │                              │
 │    or reboot (commit)      │                              │
 │  • gc, unclaim, go-remote  │                              │
 │  • claim state, usrmeta    │                              │
 └─────────────┬──────────────┘                              │
               │ device live on the test's revision          │
               ▼                                             │
 ┌────────────────────────────┐                              │
 │  Run test  (exec_test)     │──────────────────────────────┘
 │  • run resources/test      │
 │  • diff vs golden output   │
 └─────────────┬──────────────┘
               │ all tests done
               ▼
 ┌────────────────────────────┐
 │  Teardown  (once)          │   per target:
 │  • unclaim/delete, poweroff│   • lenient pantavisor shutdown
 └────────────────────────────┘
```

This loop is repeated until the tester has executed the full flat queue sent by the host,
pre-sorted for time optimization (claim-needing tests first, equal configs adjacent to avoid
unnecessary re-types).

## Build

Build the distro tarball as described in [get-started.md](../../get-started.md) — build target
`pantavisor-appengine-distro`.

When changes are made in meta-pantavisor (test scripts, `test.json`, expected output, container
recipes), a rebuild is required to pick them up. Because BitBake may not detect file-level
changes inside a recipe's `files/` directory, force a clean rebuild when touching test data:

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'bitbake -c cleansstate pantavisor-pvtests-local pantavisor-pvtests-remote pantavisor-appengine-distro pantavisor-bsp pantavisor-default-skel \
     && bitbake -c build pantavisor-appengine-distro'
```

## Install

Extract the tarball and load the Docker images as described in the tarball's own `README.md`.
When working directly on the build machine, the deploy directory already contains an unpacked
directory, you can cd into it and run `test.docker.sh` without extracting anything.

## Invocation

`./test.docker.sh -h` lists every command, flag, path selector and environment override. The
tarball `README.md` has ready-made examples for the appengine pool and for real devices.

## Reading a run

Every run creates a workspace that contains a `README.md` inside that documents the full
layout, the log format andits four sources, the useful greps, and how to read valgrind output.
