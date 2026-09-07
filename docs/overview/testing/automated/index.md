---
title: "Automated Testing"
sidebar_position: 1
description: "Building the pvtest appengine distro and its container fixtures. The suite itself is documented in the pantavisor repo."
---
# Building the pvtest distro

pvtest — the automated integration suite — **lives in the pantavisor repo**, under `pvtest/`:
the tester runner, the host orchestrators (`test.docker.sh`, `test.native.sh`) and the test data.
meta-pantavisor assembles those into the distro tarball you run, and owns the `pv-example-*`
container fixtures the tests run against.

So this page covers **building** that tarball and its fixtures. Everything about *using* the
result — architecture, running the suite, debugging, authoring tests, real devices, the test
list — is in pantavisor:

- [The pvtest Harness](../../../../pantavisor/testing/pvtest-harness.md) — architecture, execution
  models, file layout, reading a run
- [Running and Authoring pvtests](../../../../pantavisor/testing/appengine.md) — the appengine pool,
  debugging, adding tests and fixtures, authoring rules
- [Running Against a Real Device](../../../../pantavisor/testing/device.md) — manifest,
  setbootconfig, per-MACHINE tarballs, expected outcomes
- [Running Without a Container Runtime](../../../../pantavisor/testing/native.md) — `test.native.sh`
- [pvtest List](../../../../pantavisor/testing/pvtest-list.md) — every test, with status

## What this layer contributes

| File | Role |
|---|---|
| `recipes-pv/pantavisor/pantavisor_git.bb` | `do_deploy` stages the host half and the suites out of the pantavisor source tree |
| `recipes-pv/pantavisor/pantavisor-appengine-distro.bb` | packs it all into the tarball; `PV_PVTEST_CONTAINERS`/`_XCONNECT` name the fixtures to build and stage |
| `recipes-containers/pv-examples/` | every `pv-example-*` fixture, the containers the *manual* testplans use, and `pv-avahi`/`pv-avahi-browse` — shipped product containers two xconnect tests happen to use |
| `classes/container-pvrexport.bbclass` | inherited by every fixture recipe |

## Build

Build the distro tarball as described in [get-started.md](../../get-started.md) — build target
`pantavisor-appengine-distro`.

Test data (test scripts, `test.json`, expected output) lives in pantavisor, so a rebuild only
picks it up if the build is pointed at the pantavisor checkout that has it — either by bumping
`PANTAVISOR_SRCREV`, or with `devtool modify pantavisor` for local work:

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'devtool modify pantavisor && bitbake -c build pantavisor-appengine-distro'
```

Force a clean rebuild when BitBake does not notice the change:

```bash
./kas-container shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c \
    'bitbake -c cleansstate pantavisor pantavisor-appengine-distro pantavisor-bsp pantavisor-default-skel \
     && bitbake -c build pantavisor-appengine-distro'
```

### Building a specific pantavisor branch

`devtool modify` repoints the recipe source, which is all a pantavisor branch changes — the
fixture recipes are in this layer and come from the checkout you are building in:

```bash
kas shell <configs> -c \
    'devtool modify pantavisor && … git checkout <sha> && … \
     bitbake -c build pantavisor-appengine-distro'
```

This is what the pantavisor repo's own `onpush-pvtest.yaml` does to test a branch before it is
pinned as `PANTAVISOR_SRCREV`.

## Install

Extract the tarball and load the Docker images as described in the tarball's own `README.md`.
When working directly on the build machine, the deploy directory already contains an unpacked
directory — cd into it and run `test.docker.sh` without extracting anything.

`install-docker` loads the netsim, tester and appengine images tagged `latest`. On a host
shared by several concurrent jobs on one docker daemon, set `PVTEST_IMAGE_TAG` before
`install-docker` so each job's images and runs get their own tag instead of colliding on
`latest`:

```bash
PVTEST_IMAGE_TAG=jobA ./test.docker.sh install-docker
PVTEST_IMAGE_TAG=jobA ./test.docker.sh run local
PVTEST_IMAGE_TAG=jobA ./test.docker.sh clean-docker   # untags/removes only this job's images/containers
```

## Building a single fixture

A fixture recipe is a container image, independent of pantavisor's source, so no `devtool modify`
is involved:

```bash
kas shell kas/build-configs/release/docker-x86_64-scarthgap.yaml -c 'bitbake <name>'
# -> build/tmp-scarthgap/deploy/images/<machine>/<name>.pvrexport.tgz
```

Drop the result into an already-installed distro with `./test.docker.sh install-tarballs` — see
[Adding a new container for a test](../../../../pantavisor/testing/appengine.md#adding-a-new-container-for-a-test).

## Building fixtures for another MACHINE

The example containers are ordinary `image` + `container-pvrexport` recipes with no arch
literals, so building *just those recipes* for the board's MACHINE is enough — any build config
with the right MACHINE and the right signing CA will do:

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

`PV_PVTEST_CONTAINERS` in `recipes-pv/pantavisor/pantavisor-appengine-distro.bb` is the
authoritative list of what the suites consume. What the resulting tarballs are bound to
(architecture, signing CA) and how to install them on a board is in
[Running Against a Real Device](../../../../pantavisor/testing/device.md#building-target-tarballs).
