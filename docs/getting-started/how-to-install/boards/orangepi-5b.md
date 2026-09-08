# Flashing: Orange Pi 5B

**Flash method:** rkdeveloptool via pv-flash-bundle (eMMC) — see [rockchip.md](../rockchip.md)

**Image artifact:** `pv-flash-bundle-orangepi-5b.tar.gz` (eMMC) or
`pantavisor-starter-orangepi-5b*.wic.gz` (SD card)

**Build:** `kas build kas/build-configs/release/rockchip-orangepi-5b-scarthgap.yaml` — see the
[build config table](/meta-pantavisor/overview/build-system#build-configs).

## Hardware overview

The Orange Pi 5B is a Rockchip **RK3588S** SBC (4×Cortex-A76 + 4×Cortex-A55)
with on-board eMMC and Wi-Fi/Bluetooth. The BSP comes from
JeffyCN/meta-rockchip (`kas/platforms/rockchip.yaml`).

Two USB-visible connectors matter for flashing:

| Connector | Use |
|---|---|
| USB-C | Power **and** the USB OTG port `rkdeveloptool` talks to |
| Maskrom button | Small button next to the USB-C / headphone jack; hold it to force USB Maskrom mode |

## SD card boot

`pantavisor-starter-orangepi-5b*.wic.gz` boots straight from a microSD card
with no eMMC changes. Write it per [SD Card](../sdcard.md) and insert it; the
RK3588S boot ROM tries SD before eMMC. Good for evaluation without touching
eMMC.

## rkdeveloptool (USB flash to eMMC)

### 1. Enter Maskrom mode

1. Power the board off; remove any bootable microSD card.
2. Hold the **Maskrom** button.
3. Plug the USB-C cable into your host.
4. Release the button after ~2 s.

### 2. Flash

Using the self-contained bundle (recommended — no `rkdeveloptool` install needed):

```bash
tar xzf pv-flash-bundle-orangepi-5b.tar.gz
cd pv-flash-bundle-orangepi-5b
./flash.sh
```

`flash.sh` waits for the Maskrom device, sends `loader.bin` to SRAM, writes the
whole `.wic` from sector 0 (GPT + idbloader + U-Boot + rootfs), and reboots.
See [Flashing Rockchip devices](../rockchip.md) for prerequisites
(`libusb-1.0`, udev rule) and troubleshooting.

### 3. Boot

The board reboots from eMMC automatically after `rkdeveloptool rd`. Remove the
USB-C cable and re-attach power if it was only USB-powered.

## Notes

- Keep no bootable microSD card inserted while flashing — `rkdeveloptool wl 0`
  writes to the first storage the loader enumerates, which should be eMMC but
  can be the SD card if one is present.
- The build produces `.wic.gz` + `.wic.bmap`; only the `.wic.gz` is used by
  `flash.sh`.
