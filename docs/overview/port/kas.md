---
title: Building
sidebar_position: 4
description: Learn how to build Pantavisor Linux images using Kas. Complete guide to the build system, configuration, and compilation.
---

With a [platform](./platform.md) and [machine](./machine.md) file in place, you can build the Pantavisor image and flash it to the board.

## Running the Build

All builds run through `kas-container`, a Docker wrapper that provides a reproducible Yocto environment without requiring a local Yocto toolchain install.

### Option A — Interactive Menu

`kas menu Kconfig` opens a menu-driven configuration interface:

```bash
./kas-container menu Kconfig
```

Walk through the prompts:

1. **Build Type**: Choose `singleconfig` (or `multiconfig` for separate initramfs and container builds; `appengine` / `appengine-custom` build the Docker-based appengine instead of a BSP image).
2. **Codename**: Select the Yocto release — `scarthgap` (primary, CI-tested) or `kirkstone` (supported).
3. **Build Target**:
   - `pantavisor-starter` — Minimal image with networking, Wi-Fi, and the pvr-sdk container pre-installed.
   - `pantavisor-remix` — Same base, but lets you choose which containers to pre-install.
   - `pantavisor-bsp` — BSP-only image (no pre-installed containers).
4. **Machine**: Select your target from the list — your new machine file should appear here.

After saving the configuration, the build starts automatically, or run it manually:

```bash
./kas-container build .config.yaml
```

### Option B — Direct Config

Build directly with a known config without the menu:

```bash
./kas-container build kas/machines/verdin-imx8mm.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:kas/build-configs/build-base-starter.yaml
```

The colon-separated fragments are merged by KAS in order. This is the same format used in `.github/machines.json`.

For the general build workflow (worktrees, build modes, targets, smoke tests), see [Get started with meta-pantavisor](/meta-pantavisor/overview/get-started).

## Build Output

Artifacts land in:

```
build/tmp-scarthgap/deploy/images/<machine>/
```

Key files:

| Artifact | Description |
|----------|-------------|
| `*.wic` / `*.wic.bz2` | Flashable disk image (SD card or eMMC) |
| `pantavisor-initramfs-*.cpio.gz` | Pantavisor initramfs |
| `*.pvrexport.tgz` | Pantavisor container export bundles |
| `*.manifest` | Package list for the image |

## Flashing the Image

### pvflasher (recommended)

[pvflasher](https://github.com/pantavisor/pvflasher) is Pantacor's cross-platform flashing tool. It handles `.wic` and `.wic.bz2` images without manual decompression and verifies the write with SHA256.

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/pantavisor/pvflasher/main/scripts/install.sh | bash

# List candidate target devices
pvflasher list

# Flash
pvflasher copy pantavisor-starter-verdin-imx8mm.wic.bz2 /dev/sdX
```

Replace `/dev/sdX` with your SD card or eMMC device.

### dd (alternative)

```bash
# Decompress first
bunzip2 pantavisor-starter-verdin-imx8mm.wic.bz2

# Write — double-check of= before running
sudo dd if=pantavisor-starter-verdin-imx8mm.wic of=/dev/sdX bs=4M conv=fsync status=progress
```

> **Warning:** `dd` overwrites the target without confirmation. Verify your device path with `lsblk` first.

### Board-Specific Flashing

Some boards use special flashing utilities instead of SD card:

| Board family | Tool / method |
|---|---|
| Toradex Verdin / Colibri | pv-flash-bundle — self-contained UUU bundle, no Tezi |
| NXP i.MX (Variscite) | `uuu` (Universal Update Utility) |
| Rockchip | SD card via Maskrom-disabled boot |
| Raspberry Pi | SD card always; all RPi variants supported by `rpi.yaml` multi-kernel build |

See the install guides for details: [SD card](/meta-pantavisor/getting-started/how-to-install/sdcard), [pv-flash-bundle](/meta-pantavisor/overview/pv-flash-bundle), [NXP uuu](/meta-pantavisor/getting-started/how-to-install/uuu), and the [supported boards overview](/meta-pantavisor/getting-started/how-to-install).
