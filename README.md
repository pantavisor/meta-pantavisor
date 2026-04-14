# meta-pantavisor

Yocto/OpenEmbedded layer for building [Pantavisor](https://pantavisor.io), a container-based embedded Linux system runtime. Provides recipes, BitBake classes, and KAS configurations for building complete BSP images with container support.

## Quick Start

```bash
# Interactive configuration menu
kas menu Kconfig

# Build for x86_64 (appengine / Docker)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

# Build for Raspberry Pi
./kas-container build kas/machines/rpi.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml
```

See [docs/how-to-build/get-started.md](docs/how-to-build/get-started.md) for the full guide.
See [docs/how-to-build/pantavisor-development.md](docs/how-to-build/pantavisor-development.md) for iterating on Pantavisor source code with the workspace overlay.

## Documentation

| Section | Description |
|---------|-------------|
| [docs/overview/](docs/overview/) | Layer architecture, build system, CI/CD |
| [docs/how-to-build/](docs/how-to-build/) | Building images, workspace dev ([pantavisor-development.md](docs/how-to-build/pantavisor-development.md)), container authoring |
| [docs/how-to-install/](docs/how-to-install/) | Flashing to hardware |
| [docs/examples/](docs/examples/) | xconnect service mesh examples |
| [docs/testing/](docs/testing/) | Test plans and appengine testing |

## Resources

- [Pantavisor Documentation](https://docs.pantahub.com/)
- [Pantavisor Community](https://community.pantavisor.io)

## CI Build Status

### Stable [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_STABLE_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/imx8mn-var-som.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-stable/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_STABLE_END -->

### Release Candidate [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_RC_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/imx8mn-var-som-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest-rc/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_RC_END -->
