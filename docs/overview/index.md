---
title: "Structure"
description: "How meta-pantavisor is organised: KAS configurations, Yocto layer layout, BitBake classes, and the build architecture."
sidebar_position: 1
---

# Structure

meta-pantavisor is the Yocto/OpenEmbedded layer that builds Pantavisor-based
BSP images for embedded Linux. It provides recipes, BitBake classes, and KAS
configurations for producing initramfs images and [container](glossary.md#container)
pvrexport bundles.

This section covers the project structure, build system architecture, and how
the layer is organized. Start here, then follow the build guide below.

**Just want to deploy your own container onto an existing device?** Skip the
build guide — grab a ready-made image via [Starter Image](images.md) / [Flashing Images](flashing-images.md) and go straight to [Develop applications](../getting-started/develop/index.md). The build guide below is
for building your own custom image from source.

**Coming from Buildroot, Mender, RAUC, or another build/update system?** See
[Benchmarks](../getting-started/benchmarks) for a direct comparison before
committing to the Yocto/BitBake build guide below.

## Topics

1. [Layer Layout](meta-pantavisor.md) — directory structure, key recipes, BitBake classes, `PANTAVISOR_FEATURES`, and Yocto compatibility
2. [Build System](build-system.md) — KAS configuration hierarchy, multiconfig architecture, build outputs, and the relationship between targets
3. [Starter Image](images.md) — how `pantavisor-starter` composes core containers with the BSP into the initial device trail
4. [Flashing Images](flashing-images.md) — where to get a ready-made image (pantavisor.io/downloads), pvflasher, and which flashing method applies to your board
5. [Boot Flow](boot-flow.md) — how `boot.cmd.pvgeneric` boots Pantavisor: FIT/trail loading, try-boot, MMC vs NAND/UBIFS, and `PV_BOOT_OEMARGS`
6. [Flashing NXP devices](pv-flash-bundle.md) — the UUU factory-flash archive recipe (Toradex, Variscite, NXP MEK): design, `PV_FLASH_*` variables, and how to wire up a new machine

## Build Guide

7. [Get Started](get-started.md) — prerequisites, repository setup, git worktrees, and your first KAS build
8. [Supported Devices](supported-device.md) — machines supported and built by CI
9. [Pantavisor Development](pantavisor-development.md) — build against a local pantavisor source checkout using the workspace overlay
10. [Container Development](container-development.md) — author and iterate on app containers: recipe structure, pvrexport, and local testing
11. [Manifest Audit](manifest-audit.md) — audit rootfs content with `pv-manifest-audit` and enforce strict mode
12. [Component Docs](component-docs.md) — generate per-component documentation tarballs from the build
13. [Bootchartd](bootchartd.md) — enable boot performance profiling with bootchartd in Pantavisor images

## Continuous Integration

- [Continuous Integration](ci/index.md) — CI system overview, machine matrix, release builds, tag sync, and docs publishing

## Also in this section

- [Porting Pantavisor](port/index.md) — add support for a new board: platform
  and machine KAS files, CI registration, and building.
- [Composable Firmware](composable-firmware.md) — what "composable firmware"
  actually means here.
- [Examples](examples/index.md) — worked xconnect and pvwificonnect examples.
- [Testing](testing/index.md) — development and automated test workflows.
- [Glossary](glossary.md) — every term used throughout these docs, defined
  in one place.
