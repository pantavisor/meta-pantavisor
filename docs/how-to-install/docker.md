# Running Pantavisor AppEngine

Pantavisor AppEngine init mode lets you run Pantavisor in your already set up
Linux distro — a non-invasive way to experiment with the platform without
reflashing device storage.

> **Note:** The AppEngine approach does not achieve the minimal system
> specifications that Pantavisor normally targets. It is designed for container
> engine prototyping, development, and testing rather than production
> deployments.

For full requirements and installation options see:
**[docs.pantahub.com/requirements-appengine](https://docs.pantahub.com/requirements-appengine/)**

## Building with meta-pantavisor

The `pantavisor-appengine-distro` recipe produces a ready-to-load Docker image
together with `test.docker.sh`, the test runner script.

```bash
kas build kas/machines/docker-x86_64.yaml:kas/appengine-base.yaml:kas/build-configs/build-appengine-distro.yaml
```

The output tarball is at:

```
build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-distro-docker-x86_64*.tar.gz
```

## Loading the image

Use `test.docker.sh` to load all required Docker images in one step:

```bash
./test.docker.sh load-deps
```

## Running tests

Pantavisor AppEngine ships with two separate test suites that validate
different aspects of the runtime.

### pvtests-local

[pvtests-local](https://gitlab.com/pantacor/pvtests-local) validates the local
Pantavisor experience inside a Docker container. It tests core components
including `pvcontrol`, `pvtx`, and `pvr`.

Clone the repository:

```bash
git clone https://gitlab.com/pantacor/pvtests-local
```

Run all tests:

```bash
./test.docker.sh run -v pvtests-local
```

List available tests:

```bash
./test.docker.sh ls
```

Run a specific test by number:

```bash
./test.docker.sh run -v pvtests-local:000
```

### pvtests-remote

[pvtests-remote](https://gitlab.com/pantacor/pvtests-remote) validates the
remote Pantavisor experience — OTA updates, Pantahub connectivity, and remote
control operations. Pantahub credentials must be configured via environment
variables before running these tests.

Clone the repository:

```bash
git clone https://gitlab.com/pantacor/pvtests-remote
```

Run all tests:

```bash
./test.docker.sh run -v pvtests-remote
```

Run a specific test by number:

```bash
./test.docker.sh run -v pvtests-remote:000
```

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
