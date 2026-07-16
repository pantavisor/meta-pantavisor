---
sidebar_position: 1
---
# Flashing via SD Card (WIC images)

Most Pantavisor machines produce a `.wic` image that can be written directly
to an SD card. This page covers the generic procedure. Board-specific pages
note any extra steps such as boot-mode switches.

## Prerequisites

- SD card (8 GB minimum recommended)
- Linux, Windows, or macOS host

## Locating the image

After a successful build the WIC image is at:

```
build/tmp-scarthgap/deploy/images/<machine>/pantavisor-starter-<machine>*.wic
```

It may also be compressed as `.wic.bz2`, `.wic.gz` or `.wic.zst` depending on
the BSP (Raspberry Pi uses `.wic.bz2`, NXP i.MX uses `.wic.gz`, Variscite uses
`.wic.zst`). pvflasher flashes compressed images directly; if using `dd`,
decompress first:

```bash
bunzip2 pantavisor-starter-<machine>*.wic.bz2   # or gunzip / unzstd
```

## Writing to SD card with pvflasher (recommended)

**pvflasher** is Pantacor's open-source flashing tool. It works on Linux,
Windows, and macOS and offers both a GUI and a CLI. Key features:

- Writes `.wic` images and compressed variants (`.wic.bz2`, `.wic.gz`,
  `.wic.zst`, `.wic.xz`) without manual decompression
- Block-map (`.bmap`) acceleration for significantly faster flashing
- Automatic SHA256/SHA512 verification after write
- Built-in safety checks to prevent writing to system drives
- GUI with integrated Pantavisor release browser — select a channel, version,
  and device profile, then download and flash in one step

### Install pvflasher

```bash
# Linux / macOS
curl -fsSL https://raw.githubusercontent.com/pantavisor/pvflasher/main/scripts/install.sh | bash

# Windows (run PowerShell as Administrator)
irm https://raw.githubusercontent.com/pantavisor/pvflasher/main/scripts/install.ps1 | iex
```

Or build from source — see the
[pvflasher repository](https://github.com/pantavisor/pvflasher) for the
Developer Guide.

### Flash with the CLI

```bash
# Find the target disk
pvflasher list

# Flash the image (compressed images work directly)
pvflasher copy pantavisor-starter-<machine>*.wic.bz2 /dev/sdX
```

Replace `/dev/sdX` with your SD card device (e.g. `/dev/sdb`, `/dev/mmcblk0`).
On Windows use `\\.\PhysicalDriveN` (run as Administrator).

If you don't have an image yet, `pvflasher install` launches an interactive
installer right in the terminal: it lists the official release channels
(stable, release-candidate) and versions, then downloads and flashes your
pick in one go. You can also re-check a flashed card against its block map
with `pvflasher verify`.

### Flash with the GUI

1. Open pvflasher
2. Select the `.wic` image file
3. Select the target SD card
4. Click **Flash**

## Writing to SD card with dd (alternative)

> **Warning:** Double-check `of=` before running — `dd` overwrites the target
> without confirmation.

```bash
# Identify your SD card device
lsblk

# Unmount any auto-mounted partitions
sudo umount /dev/sdX*

# Write the image
sudo dd if=pantavisor-starter-<machine>*.wic of=/dev/sdX bs=4M conv=fsync status=progress
```

## Boot

Insert the SD card into the board and power on. Refer to your board's hardware
manual for the correct boot-mode switch settings to select SD card boot — some
boards default to SD, others require a switch change.

## Board-specific notes

| Board family | Notes |
|---|---|
| Raspberry Pi | No boot-mode switch needed; RPi always tries SD first. The `rpi.yaml` multi-kernel build supports all RPi variants including RPi 5. |
| Sunxi (Allwinner) | Most boards boot SD by default. Hold the FEL button during power-on only if entering USB recovery mode. |
| Rockchip / Radxa | If eMMC firmware takes boot priority, disable the eMMC (short its clock pads) so the boot ROM falls back to SD; the Maskrom button is for USB recovery mode instead. |
| TI BeagleBone/Play | Hold the **S2 (Boot)** button while applying power to boot from SD instead of eMMC. |
| TI AM6x EVB | Set boot switches to SD mode per the EVM hardware guide. |
| NXP i.MX8QXP MEK | Set SW2 DIP switches to SD card boot mode. |
| Coral Dev Board | Set boot switches to SD mode; see [Coral documentation](https://coral.ai/docs/dev-board/get-started/). |
| StarFive VisionFive2 | Set the boot-mode switches to the SDIO (SD card) position — see the StarFive VisionFive 2 quick start guide for the exact switch positions. |
