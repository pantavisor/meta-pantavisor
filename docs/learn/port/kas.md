+++
title = "Building"
weight = 4

# SEO Configuration
description = "Learn how to build Pantavisor Linux images using Kas. Complete guide to the build system, configuration, and compilation."
keywords = ["pantavisor build", "kas build system", "yocto build", "embedded linux build", "pantavisor compilation", "device image build", "pantavisor kas", "build configuration", "embedded development", "iot build system"]
meta_description = "Building Pantavisor Linux: Guide to building device images using the Kas build system for Pantavisor Linux."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Building Pantavisor Linux Images"
og_description = "Learn how to build Pantavisor Linux images using the Kas build system. Complete build and configuration guide."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Building Pantavisor Linux Images"
twitter_description = "Learn how to build Pantavisor Linux images using the Kas build system"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/port/kas/"
+++


With a [platform](../platform/) and [machine](../machine/) file in place, you can build the Pantavisor image and flash it to the board.

## Running the Build

All builds run through `kas-container`, a Docker wrapper that provides a reproducible Yocto environment without requiring a local Yocto toolchain install.

### Option A — Interactive Menu

`kas menu Kconfig` opens a menu-driven configuration interface:

```bash
./kas-container menu Kconfig
```

Walk through the prompts:

1. **Build Type**: Choose `singleconfig` (or `multiconfig` for separate initramfs and container builds).
2. **Codename**: Select the Yocto release — `scarthgap` (current) or `kirkstone` (LTS).
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
bash <(curl -fsSL https://github.com/pantavisor/pvflasher/releases/latest/download/install.sh)

# Flash
pvflasher flash --image pantavisor-starter-verdin-imx8mm.wic.bz2 --target /dev/sdX
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
| Toradex Verdin / Colibri | Toradex Easy Installer (TEZI) — `pv_teziimg.tar.xz` |
| NXP i.MX | `uuu` (Universal Update Utility) |
| Rockchip | `rkdeveloptool` or SD card in Maskrom mode |
| Raspberry Pi | SD card always; all RPi variants supported by `rpi.yaml` multi-kernel build |

See the board-specific flashing guides in `docs/how-to-install/` and the [Pantavisor documentation](https://docs.pantahub.com/) for details.
