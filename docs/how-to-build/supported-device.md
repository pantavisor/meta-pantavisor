# Supported Devices

This document outlines the devices (machines) currently supported by meta-pantavisor, including those that are built automatically by our CI infrastructure.

## CI Supported Machines

The following machines are configured in our CI pipeline (`.github/machines.json`) and have artifacts built automatically:

| Machine Name | Description / Notes |
| ------------ | ------------------- |
| `sunxi-orange-pi-3lts` | Orange Pi 3 LTS (Allwinner H6) |
| `sunxi-orange-pi-r1` | Orange Pi R1 (Allwinner H2+) |
| `sunxi-bananapi-m2-berry`| Banana Pi M2 Berry |
| `imx8qxp-b0-mek` | NXP i.MX 8QXP MEK |
| `raspberrypi-armv8` | Raspberry Pi (ARMv8 / 64-bit) |
| `rpi` | Raspberry Pi (ARMv7 / 32-bit) |
| `colibri-imx6ull` | Toradex Colibri iMX6ULL |
| `radxa-rock5a` | Radxa ROCK 5A |
| `imx8mn-var-som` | Variscite i.MX 8M Nano SOM |
| `imx8mm-var-dart` | Variscite DART-MX8M-MINI |
| `docker-x86_64` | AppEngine testing container (x86_64) |

> [!NOTE]
> For an up-to-date programmatic list of what is built, always refer to [`.github/machines.json`](../../.github/machines.json). If you add a new machine, remember to run `.github/scripts/makeworkflows` to regenerate the GitHub Actions workflows.

## Downloading Images

The images built by our CI for the machines listed above are automatically placed on our downloads page for easy access. You can find and download the pre-built artifacts at: [https://pantavisor.io/downloads/](https://pantavisor.io/downloads/)

## Building for a Device

To learn how to build an image for one of these supported devices, check out the following guides:

- [**Get Started**](get-started.md): Walkthrough of your first build using `kas`.
- [**Pantavisor Development**](pantavisor-development.md): Learn how to build using a workspace overlay for local development.

## Installing the Image

Once you have built an image for your device, you need to flash it or install it on the target hardware. The installation process varies by board type:

- See the [**How to Install Overview**](../how-to-install/index.md) for general flashing instructions.
- Refer to board-specific guides such as [SD Card installation](../how-to-install/sdcard.md), [Toradex Easy Installer (Tezi)](../how-to-install/tezi.md), or [NXP UUU](../how-to-install/uuu.md) depending on your target machine.
