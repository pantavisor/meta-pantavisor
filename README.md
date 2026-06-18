# meta-pantavisor

Yocto/OpenEmbedded layer for building [Pantavisor](https://pantavisor.io), a container-based embedded Linux system runtime. Provides recipes, BitBake classes, and KAS configurations for building complete BSP images with container support.

## Quick Start

```bash
# Interactive configuration menu
kas menu Kconfig

# Build for x86_64 (appengine / Docker)
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml

# Build for Raspberry Pi
./kas-container build kas/machines/rpi.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml
```

### Working on multiple branches in parallel

Use the helper scripts — **not** plain `git worktree add` — so build/sstate-cache and build/downloads stay shared across worktrees (cuts cold-build time from hours to minutes):

```bash
./worktree-create.sh ../meta-pv-feat-foo -b feat/foo origin/master
./worktree-remove.sh  ../meta-pv-feat-foo
```

Both wrap `git worktree add/remove`; everything after `<path>` passes through. See [docs/how-to-build/get-started.md#working-on-multiple-branches-git-worktrees](docs/how-to-build/get-started.md).

### See also

- [docs/how-to-build/get-started.md](docs/how-to-build/get-started.md) — full first-build guide.
- [docs/how-to-build/pantavisor-development.md](docs/how-to-build/pantavisor-development.md) — iterating on Pantavisor source via the workspace overlay (`kas/with-workspace.yaml`). Always use this rather than a separate Pantavisor git checkout — devtool manages the workspace and external checkouts aren't reachable from inside `kas-container`.
- [docs/overview/xconnect-services.md](docs/overview/xconnect-services.md) — service-IP layer (ClusterIPs, `<service>.pv.local`, k8s-Services-style mediation).
- [docs/how-to-build/xconnect-services.md](docs/how-to-build/xconnect-services.md) — adding a TCP service to your container.

## Documentation

| Section | Description |
|---------|-------------|
| [docs/overview/](docs/overview/) | Layer architecture, build system, CI/CD |
| [docs/how-to-build/](docs/how-to-build/) | Building images, workspace dev ([pantavisor-development.md](docs/how-to-build/pantavisor-development.md)), container authoring |
| [docs/how-to-install/](docs/how-to-install/) | Flashing to hardware |
| [docs/examples/](docs/examples/) | xconnect service mesh examples ([service-IP overview](docs/overview/xconnect-services.md), [adding a service](docs/how-to-build/xconnect-services.md)) |
| [docs/testing/](docs/testing/) | Test plans and appengine testing |

## Resources

- [Pantavisor Documentation](https://docs.pantahub.com/)
- [Pantavisor Community](https://community.pantavisor.io)

## CI Build Status

### Stable [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_STABLE_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8mn-var-som-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_STABLE_END -->

### Release Candidate [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_RC_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8mn-var-som-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_RC_END -->
