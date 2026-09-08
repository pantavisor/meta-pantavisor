---
sidebar_position: 5
---
# Flashing Rockchip devices

Rockchip RK3588S boards flash their on-board eMMC over USB with
[`rkdeveloptool`](https://github.com/rockchip-linux/rkdeveloptool), driving the
SoC's USB **Maskrom** recovery mode. This writes eMMC without removing it from
the board and recovers a board even when its current bootloader is broken.

For board-specific hardware setup (Maskrom button, USB port) see:

- [Orange Pi 5B](boards/orangepi-5b.md)

## pv-flash-bundle (recommended)

These machines build `pv-flash-bundle` (`recipes-bsp/pv-flash/pv-flash-bundle.bb`)
as part of their release KAS target list. It packages a portable `rkdeveloptool`
binary, the Rockchip USB loader (`loader.bin`), the compressed WIC image, and a
generated `flash.sh` into a single self-contained archive — no separate
`rkdeveloptool` install needed on the host. See
[pv-flash-bundle](../../overview/pv-flash-bundle.md) for how it's assembled.

```
build/tmp-scarthgap/deploy/images/<machine>/pv-flash-bundle-<machine>.tar.gz
```

```bash
tar xzf pv-flash-bundle-<machine>.tar.gz
cd pv-flash-bundle-<machine>
./flash.sh
```

`flash.sh` decompresses the bundled WIC image (`.wic.zst` via `zstd`, else
`.wic.gz` via `zcat`), waits for a device in Maskrom mode, then runs:

```bash
sudo ./rkdeveloptool db loader.bin   # load DDR init + usbplug into SoC SRAM
sudo ./rkdeveloptool wl 0 <image>.wic # write the whole disk image from sector 0
sudo ./rkdeveloptool rd              # reboot
```

`wl 0` writes the full GPT image — partition table, `idbloader`, U-Boot and
rootfs — so no separate bootloader step is needed.

### Prerequisites

- USB-C cable from the board's USB-C (OTG) port to the host.
- `libusb-1.0` on the host — the bundled `rkdeveloptool` links it dynamically:
  ```bash
  sudo apt install libusb-1.0-0 zstd
  ```
- Root, or a udev rule for the Rockchip USB vendor ID:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2207", MODE="0666"' \
      | sudo tee /etc/udev/rules.d/70-rockchip-rkdeveloptool.rules
  sudo udevadm control --reload-rules
  ```

### Entering Maskrom mode

1. Power the board off and remove any bootable SD card (otherwise
   `rkdeveloptool` may target the SD card instead of eMMC).
2. Hold the **Maskrom** button.
3. Connect the USB-C cable to the host.
4. Release the button after ~2 s.

Verify the host sees it:

```bash
sudo ./rkdeveloptool ld
# DevNo=1  Vid=0x2207,Pid=0x350b,LocationID=...  Maskrom
```

`flash.sh` polls for this automatically, so you can also start `./flash.sh`
first and then enter Maskrom mode.

## Notes

- After `db`, the SoC re-enumerates in Loader mode; `flash.sh` waits 2 s before
  `wl`. If `wl` reports no device, re-run `rkdeveloptool ld` — it should now show
  `Loader` rather than `Maskrom`.
- To reflash, just power-cycle back into Maskrom mode and re-run `./flash.sh`.
- The Orange Pi 5B loader (`loader.bin`) is the JeffyCN/meta-rockchip Rockchip
  Miniloader; it carries the `usbplug` that services `wl`. Mainline-U-Boot
  Rockchip BSPs ship no such loader — see
  [pv-flash-bundle: adding a new machine](../../overview/pv-flash-bundle.md#adding-a-new-machine).
