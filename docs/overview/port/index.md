---
title: Porting Pantavisor
sidebar_position: 11
description: "Add support for a new board to meta-pantavisor: platform and machine KAS files, CI registration, and building."
---

This section covers how to add support for a new device or hardware platform to `meta-pantavisor`.

**Where this job ends:** porting is done once `pantavisor-bsp` boots Pantavisor
successfully on the new board. Apps and other containers are a separate
concern, covered in [Container Development](../container-development.md) —
you don't need to touch container recipes to bring up a new machine.

## Build System Overview

`meta-pantavisor` uses **Yocto/OpenEmbedded** with **KAS** as the configuration and orchestration layer: builds run through `./kas-container build <config.yaml>`, where the config is composed from layered YAML fragments — base settings (`kas/bsp-base.yaml`), a Yocto release (`kas/scarthgap.yaml`), a platform (`kas/platforms/<family>.yaml`), and a machine (`kas/machines/<device>.yaml`). See the [Build system overview](../build-system) for the full hierarchy.

Supported Yocto releases (both LTS): **scarthgap** (primary, CI-tested) and **kirkstone** (supported).

## Porting Process

Adding a new device involves three steps, each covered in its own page:

1. **[Platform](./platform.md)** — Create `kas/platforms/<family>.yaml` to declare the vendor BSP layers for a new hardware family. Skip this step if a suitable platform file already exists (check `kas/platforms/`).

2. **[Machine](./machine.md)** — Create `kas/machines/<device>.yaml` to bind the platform to a specific Yocto `MACHINE` name and set any device-specific BitBake variables.

3. **[Building](./kas.md)** — Run the build, locate the output artifacts, and flash the image to the board.

## Registering a Machine for CI

After creating a machine file:

1. Add an entry to `.github/machines.json`.
2. Regenerate the workflow files with `.github/scripts/makeworkflows`.
3. Run `.github/scripts/makemachines` to generate the pinned release lockfile `kas/build-configs/release/<machine>-scarthgap.yaml`.
4. Commit `machines.json`, the generated workflows, and the lockfile together.

See the [CI overview](../ci/overview.md) for the machine entry format and optional properties.

## Existing Platforms and Machines

Before starting, check whether your hardware is already supported:

- Platforms: `kas/platforms/` — includes `freescale.yaml`, `toradex.yaml`, `raspberrypi.yaml`, `rockchip.yaml`, `sunxi.yaml`, `ti.yaml`, `variscite.yaml`, and more
- Machines: `kas/machines/` — includes Raspberry Pi, Variscite, Toradex Verdin/Colibri, NXP MEK, Rockchip, RISC-V VisionFive2, and QEMU targets
