---
sidebar_position: 2
---
# Running Pantavisor AppEngine

Pantavisor AppEngine init mode lets you run Pantavisor in your already set up
Linux distro — a non-invasive way to experiment with the platform without
reflashing device storage.

> **Note:** The AppEngine approach does not achieve the minimal system
> specifications that Pantavisor normally targets. It is designed for container
> engine prototyping, development, and testing rather than production
> deployments.

There's no pre-built AppEngine tarball to download — build one yourself via
[Get Started](../../overview/get-started.md) (this repo's Yocto/BitBake
toolchain, build target `pantavisor-appengine-distro`), then continue below.
For additional background beyond this page, see
[docs.pantahub.com/requirements-appengine](https://docs.pantahub.com/requirements-appengine/).

## First-time system setup

On a fresh machine, install all required system dependencies (Docker, QEMU, kernel modules, apt packages) before running any tests:

```bash
./test.docker.sh install-deps
```

This is interactive and will prompt before making system changes. You only need to run this once per machine.

## Loading the image

### From the build directory (no extraction needed)

After building `pantavisor-appengine-distro`, the deploy directory contains an unpacked directory alongside the tarball:

```
build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-distro-docker-x86_64-<version>/
```

cd into it and load the Docker images directly — no extraction step needed:

```bash
cd build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-distro-docker-x86_64-<version>/
./test.docker.sh install-docker
```

### From a tarball

Extract the tarball and load all required Docker images into a working directory:

```bash
mkdir -p <workdir> && cd <workdir>
tar -xzf /path/to/pantavisor-appengine-distro-docker-x86_64-*.tar.gz
chmod +x test.docker.sh
./test.docker.sh install-docker
```

Run `install-docker` every time you install from a new tarball — it reloads the appengine, tester, and netsim Docker images.

Both the unpacked directory and the tarball include `local/` and `remote/` test trees with test data — no separate clone step needed.

## Running tests

Pantavisor AppEngine ships with two separate test suites that validate
different aspects of the runtime.

### Local tests (`local/`)

Local tests validate the Pantavisor runtime entirely within the appengine
container. They cover core, lifecycle, runtime, control, security, and
services functionality.

Run all local tests:

```bash
./test.docker.sh -v run local
```

List available tests:

```bash
./test.docker.sh ls
```

Run a specific test:

```bash
./test.docker.sh -v run local/core/legacy-config-overload
```

Run all tests in a category:

```bash
./test.docker.sh -v run local/lifecycle
```

### Remote tests (`remote/`)

Remote tests validate Pantahub connectivity — OTA updates, device claiming,
and cloud logging. Pantahub credentials must be configured via environment
variables before running these tests.

Run all remote tests:

```bash
./test.docker.sh -v run remote
```

Run a specific test:

```bash
./test.docker.sh -v run remote/core/encrypted-pantahub-config
```

## Standalone container

Besides the test harness, you can run the appengine image as a standalone
container named `pva-test`, with a `pvtx.d` directory of `.pvrexport.tgz`
bundles to provision and a `storage-test` volume for persistent state:

```bash
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
```

The debug and reset commands below operate on this container.

## Debug commands

```bash
# Pantavisor logs
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log

# Container console log
docker exec pva-test cat /var/pantavisor/storage/logs/0/<container>/lxc/console.log

# Enter a container namespace
docker exec -it pva-test pventer -c <container>

# xconnect service graph
docker exec pva-test pvcontrol graph ls

# Daemon status
docker exec pva-test pvcontrol daemons ls
```

## Resetting state

The `pvtx.d` provisioning scripts only run once per storage volume (keyed on
`.pvtx-done`). To re-trigger provisioning:

```bash
# Option A — remove the storage volume entirely
docker rm -f pva-test
docker volume rm storage-test

# Option B — remove only the done-marker (preserves existing state)
docker exec pva-test rm /var/pantavisor/storage/.pvtx-done
docker restart pva-test
```
