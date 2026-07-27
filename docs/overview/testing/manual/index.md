---
title: "Manual Testing"
sidebar_position: 2
---
# Manual Testing

Driving an appengine container by hand, with no test harness involved — the quick loop while
coding on pantavisor or on a container recipe. For the structured pvtest suite see
[Automated Testing](../automated/index.md).

This page covers the layer's half: building the image and getting it onto your docker host.
Everything about the container once it exists — the entrypoint, its config, storage and log
layout, `pventer`/`pvcurl`/`pvcontrol` recipes, cleanup — is the runtime's own documentation,
in the pantavisor repo at `docs/overview/appengine.md`, since that is where `pv-appengine`
lives.

## Build

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml
```

To test local pantavisor changes, build with the `:kas/with-workspace.yaml` overlay.
`externalsrc` does not change task signatures, so force a fresh compile or sstate may serve a
stale binary:

```bash
./kas-container shell <cfg>:kas/with-workspace.yaml -c \
    "bitbake -c cleansstate pantavisor && bitbake pantavisor-appengine-distro"
```

Build the example containers a given test plan needs with `--target pv-example-<name>`; each
plan under [testplans/](testplans/index.md) lists its own.

BitBake may not detect file-level changes inside a recipe's `files/` directory, so force a
clean rebuild when touching container payloads or test data — see
[the automated page](../automated/index.md#build) for the full `cleansstate` incantation.

## Load

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

Container pvrexports for the appengine's first-boot `pvtx.d`:

```bash
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/
```

From here, see the pantavisor repo's `docs/overview/appengine.md` for how to start and drive
the container.

## Build-side troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| xconnect/pvcontrol/rngdaemon missing from the image | `+=` used in a distro include | Use `:append` for `PANTAVISOR_FEATURES` — `+=` clobbers the `??=` defaults from `pvbase.bbclass` |
| `path mismatch [1 link]` | Pseudo database corruption | `bitbake -c cleansstate <recipe>` |
| pvtx.d not processed at boot | Storage volume reused from a previous run | `docker volume rm storage-test` |
| Stale binary after a source change | `externalsrc` doesn't change task signatures | `bitbake -c cleansstate pantavisor` before rebuilding |

## Test plans

Per-feature plans, each a manual sequence of setup → execute → verify:

| Plan | Coverage |
|------|----------|
| [testplan-auto-recovery.md](testplans/testplan-auto-recovery.md) | Container restart policies, exponential backoff, group inheritance |
| [testplan-container-control.md](testplans/testplan-container-control.md) | Container lifecycle API (stop/start/restart, user_stopped, batch jobs) |
| [testplan-pvctrl.md](testplans/testplan-pvctrl.md) | Full pv-ctrl REST API coverage |
| [testplan-xconnect.md](testplans/testplan-xconnect.md) | xconnect service mesh (unix, D-Bus, REST, DRM, Wayland) |
| [testplan-ipam.md](testplans/testplan-ipam.md) | IPAM pool-based container networking, NAT backend selection |
| [testplan-pvtx.md](testplans/testplan-pvtx.md) | pvtx transaction tool unit tests (no Pantavisor needed) |
| [testplan-cgroup.md](testplans/testplan-cgroup.md) | cgroup HYBRID-mode destroy and no-suffix accumulation (lenient + force stop) |
