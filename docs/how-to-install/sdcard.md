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

It may also be compressed as `.wic.bz2`. pvflasher handles compressed images
automatically; if using `dd` decompress first:

```bash
bunzip2 pantavisor-starter-<machine>*.wic.bz2
```

## Writing to SD card with pvflasher (recommended)

**pvflasher** is Pantacor's open-source flashing tool. It works on Linux,
Windows, and macOS and offers both a GUI and a CLI. Key features:

- Writes `.wic` and `.wic.bz2` images without manual decompression
- Block-map (`.bmap`) acceleration for significantly faster flashing
- Automatic SHA256/SHA512 verification after write
- Built-in safety checks to prevent writing to system drives
- GUI with integrated Pantavisor release browser — select a channel, version,
  and device profile, then download and flash in one step

### Install pvflasher

```bash
# Linux / macOS
bash <(curl -fsSL https://github.com/pantavisor/pvflasher/releases/latest/download/install.sh)

# Windows (run PowerShell as Administrator)
irm https://github.com/pantavisor/pvflasher/releases/latest/download/install.ps1 | iex
```

Or build from source — see the
[pvflasher repository](https://github.com/pantavisor/pvflasher) for the
Developer Guide.

### Flash with the CLI

```bash
pvflasher flash --image pantavisor-starter-<machine>*.wic --target /dev/sdX
```

Replace `/dev/sdX` with your SD card device (e.g. `/dev/sdb`, `/dev/mmcblk0`).
On Windows use `\\.\PhysicalDriveN` (run as Administrator).

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
| Rockchip / Radxa | Hold the **Maskrom** button (or short the eMMC pads) during power-on to force SD boot when eMMC is present. |
| TI BeagleBone/Play | Hold the **S2 (Boot)** button while applying power to boot from SD instead of eMMC. |
| TI AM6x EVB | Set boot switches to SD mode per the EVM hardware guide. |
| NXP i.MX8QXP MEK | Set SW2 DIP switches to SD card boot mode. |
| Coral Dev Board | Set boot switches to SD mode; see [Coral documentation](https://coral.ai/docs/dev-board/get-started/). |
| StarFive VisionFive2 | Set RGPIO_0/RGPIO_1 switches to `0 0` (SD card boot). |
