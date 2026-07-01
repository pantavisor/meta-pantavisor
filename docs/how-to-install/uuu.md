---
sidebar_position: 4
---
# Flashing via NXP uuu (Universal Update Utility)

Some i.MX-based boards support flashing via **uuu** (Universal Update Utility),
NXP's USB-based download tool. This is useful for flashing eMMC without
removing it from the board.

For board-specific hardware setup (boot switches, jumpers) see:

- [Variscite DART-MX8M-MINI](boards/imx8mm-var-dart.md)
- [Variscite VAR-SOM-MX8M-NANO](boards/imx8mn-var-som.md)
- [NXP i.MX8QXP MEK](boards/imx8qxp-b0-mek.md)

## pv-flash-bundle (recommended)

These machines build `pv-flash-bundle` (`recipes-bsp/pv-flash/pv-flash-bundle.bb`)
as part of their release KAS target list. It packages a portable `uuu`
binary, the production `imx-boot`, the compressed WIC image, and a generated
`uuu.auto` / `flash.sh` into a single self-contained archive — no separate
`uuu` install or manual command needed on the host. See
[pv-flash-bundle](../overview/pv-flash-bundle.md) for how it's assembled.

```
build/tmp-scarthgap/deploy/images/<machine>/pv-flash-bundle-<machine>.tar.gz
```

```bash
tar xzf pv-flash-bundle-<machine>.tar.gz
cd pv-flash-bundle-<machine>
./flash.sh
```

`flash.sh` decompresses the bundled `.wic.gz` and invokes `sudo ./uuu ./`,
which reads `uuu.auto` and runs the full SDP/SDPS → fastboot → eMMC flash
sequence (the MEK's i.MX8QXP silicon uses SDPS "stream" mode instead of
plain SDP; see [pv-flash-bundle](../overview/pv-flash-bundle.md#per-machine-templates)
for the difference). Put the board into USB download mode first (see the
board-specific page linked above) and connect USB before running it.

These boards' own production bootloaders already self-enter SDP/fastboot
download mode — unlike Toradex, no separate recovery U-Boot build is needed
(see [pv-flash-bundle: why Variscite and the MEK don't need a recovery multiconfig](../overview/pv-flash-bundle.md#why-variscite-and-the-mek-dont-need-a-recovery-multiconfig)).

## Manual flashing (without pv-flash-bundle)

Useful if you already have `uuu` installed and just want to reflash a WIC
image without extracting a bundle, or for boards/builds that don't produce
one.

### Prerequisites

- USB Type-A to USB-C (or Micro-USB) cable connected to the board's USB OTG / download port
- [uuu](https://github.com/nxp-imx/mfgtools/releases) installed on the host

```bash
# Install uuu on Debian/Ubuntu
sudo apt install uuu

# Or download the binary from GitHub releases
```

### Locating the artifacts

After a successful build, the WIC image and SPL/u-boot binaries are at:

```
build/tmp-scarthgap/deploy/images/<machine>/
  pantavisor-starter-<machine>*.wic
  imx-boot-<machine>*.bin       # SPL + u-boot FIT image
```

### 1. Put the board into USB download (serial download) mode

See the board-specific page for the exact switch/jumper settings.

### 2. Connect USB and verify

```bash
# uuu should detect the board
sudo uuu -lsusb
```

You should see an `SE Blank` or `SDP:MX8M*` device listed.

### 3. Flash with uuu

#### Option A — using the WIC image directly

```bash
sudo uuu -b emmc_all imx-boot-<machine>*.bin pantavisor-starter-<machine>*.wic
```

#### Option B — using a board-vendor uuu script (Variscite)

Variscite BSPs ship a `uuu_imx_android_flash.sh` script. Refer to the
[Variscite wiki](https://variwiki.com) for the board-specific command.

### 4. Boot normally

Remove the download-mode jumper/switch, then power-cycle the board. It will
boot from eMMC.

## Notes

- uuu requires root or udev rules granting access to the USB device.
  Add the NXP vendor udev rule if you get permission errors:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1fc9", MODE="0666"' \
      | sudo tee /etc/udev/rules.d/70-nxp-uuu.rules
  sudo udevadm control --reload-rules
  ```
- The `emmc_all` profile (and the bundled `uuu.auto`) write the full WIC
  image (boot partitions + rootfs). Use `emmc` if you only want to update the
  rootfs partition manually.
