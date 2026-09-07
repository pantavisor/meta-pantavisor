---
sidebar_position: 5
---
# Supported Devices

While Pantavisor can run on virtually any device that supports Linux, meta-pantavisor offers official support for a wide range of popular hardware through its machine configurations. This ensures a smooth and tested experience for developers.

## CI Supported Machines

The following machines are configured in the CI pipeline (`.github/machines.json`) and have artifacts built automatically:

| Machine Name | Description / Notes |
| ------------ | ------------------- |
| `sunxi-orange-pi-3lts` | Orange Pi 3 LTS (Allwinner H6) — real suspend-to-RAM via [crust SCP firmware](https://github.com/crust-firmware/crust); see [testplan-wakelocks-opi3-crust.md](testing/testplans/testplan-wakelocks-opi3-crust.md) |
| `sunxi-orange-pi-r1` | Orange Pi R1 (Allwinner H2+) |
| `sunxi-bananapi-m2-berry`| Banana Pi M2 Berry |
| `imx8qxp-b0-mek` | NXP i.MX 8QXP MEK |
| `raspberrypi-armv8` | Raspberry Pi (ARMv8 / 64-bit) |
| `rpi` | Raspberry Pi — all targets. Multi-kernel multiconfig covering every board (Pi 1/2/3/4/5, Zero, Compute Module), ARMv6/ARMv7/ARMv8, 32- and 64-bit |
| `colibri-imx6ull` | Toradex Colibri iMX6ULL |
| `radxa-rock5a` | Radxa ROCK 5A |
| `rockchip-orangepi-5b` | Orange Pi 5B (RK3588S), via [JeffyCN/meta-rockchip](https://github.com/JeffyCN/meta-rockchip) |
| `imx8mn-var-som` | Variscite i.MX 8M Nano SOM |
| `imx8mm-var-dart` | Variscite DART-MX8M-MINI |
| `docker-x86_64` | AppEngine testing container (x86_64) |
| `96boards-orangepi-i96` | Orange Pi i96 (RDA8810PL). BSP in [meta-orangepi-i96](https://github.com/pantavisor/meta-orangepi-i96). No Bluetooth or WiFi AP — see the [board guide](../getting-started/how-to-install/boards/orangepi-i96.md) |

> For an up-to-date programmatic list, always refer to [`.github/machines.json`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/machines.json). If you add a new machine, remember to run `.github/scripts/makeworkflows` to regenerate the GitHub Actions workflows.
>
> The `display_name` and `description` fields in `.github/machines.json` are the
> canonical source for the friendly board name and blurb shown on the
> [downloads list](#downloading-images) — `upload.sh` copies them into
> `releases.json` at release time. Keep them in sync with the table above.

## Officially supported devices

Official support extends beyond what CI builds to include additional machines
that can be built from source.

### NXP

- imx8qxp-b0-mek
- imx8qxp-mek

### Variscite

- imx8mn-var-som — see [how-to-install/boards/imx8mn-var-som.md](../getting-started/how-to-install/boards/imx8mn-var-som.md)
- imx8mm-var-dart — see [how-to-install/boards/imx8mm-var-dart.md](../getting-started/how-to-install/boards/imx8mm-var-dart.md)

### Toradex

- colibri-imx6ull — see [how-to-install/boards/colibri-imx6ull.md](../getting-started/how-to-install/boards/colibri-imx6ull.md)
- verdin-imx8mm — see [how-to-install/boards/verdin-imx8mm.md](../getting-started/how-to-install/boards/verdin-imx8mm.md)

### Raspberry Pi Foundation

- rpi (all Raspberry Pi variants incl. RPi 5, multi-kernel multiconfig)
- raspberrypi-armv8 (e.g., Raspberry Pi 3/4)
- raspberrypi-armv7 (e.g., Raspberry Pi 2)

### Google

- Google Coral Dev Board

### Rockchip

- rockchip rk3328 evb
- rockchip rk3399pro evb
- rockchip rock64
- rockchip-nanopi-m4
- rockchip-orangepi-5b (Orange Pi 5B, RK3588S)

### Radxa

- radxa rock5a
- radxa rock5b

### Texas Instruments (TI)

- TI AM62xx EVM
- TI AM62axx EVM
- TI AM65xx EVM
- TI Beaglebone
- TI Beagleplay

### Allwinner / Sunxi

- Banana Pi M2 Berry
- NanoPi R1
- Orange Pi R1
- Orange Pi Zero Plus2 H3
- Orange Pi 3 LTS
- Orange Pi PC Plus
- Orange Pi PC2

### RISC-V

- StarFive VisionFive 2

### Don't See Your Board?

No problem! Pantavisor is designed for portability. If your device can run Linux and has a Board Support Package (BSP), it can be enabled to run Pantavisor. See the porting guides in [Porting Pantavisor](port/) for how to add new machine support.

## Downloading Images

The images built by CI are available at [https://pantavisor.io/downloads/](https://pantavisor.io/downloads/).

## Building for a Device

To learn how to build an image for one of these supported devices, check out the following guides:

- [**Get Started**](get-started.md): Walkthrough of your first build using `kas`.
- [**Pantavisor Development**](pantavisor-development.md): Learn how to build using a workspace overlay for local development.

## Installing the Image

Once you have built an image for your device, you need to flash it or install it on the target hardware. The installation process varies by board type:

- See [Flashing Images](flashing-images.md) for an overview of methods, or the [**How to Install Overview**](../getting-started/how-to-install/index.md) for general flashing instructions.
- Refer to board-specific guides such as [SD Card installation](../getting-started/how-to-install/sdcard.md), [Toradex flashing](../getting-started/how-to-install/toradex.md), or [NXP UUU](../getting-started/how-to-install/uuu.md) depending on your target machine.
