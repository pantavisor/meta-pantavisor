# Flashing Toradex Modules

Both supported Toradex modules use **UUU + pv-flash-bundle** for factory flashing.
Neither uses Toradex Easy Installer (Tezi) for the Pantavisor image.

| Machine | Storage | Flash method |
|---|---|---|
| Verdin iMX8MM | eMMC | SDP → fastboot → raw-sparse WIC |
| Colibri iMX6ULL | NAND | SDP → fastboot → NAND write + UBI |

## Why UUU instead of Tezi

The Toradex builds previously generated a Tezi-format bundle
(`pv_teziimg.tar.xz`) requiring the Toradex Easy Installer host application.
Both machines now use the `pv-flash-bundle` recipe, which:

- Ships a **self-contained bundle** — UUU binary, recovery U-Boot, `uuu.auto`
  script, and the image payload — in a single `.tar.gz`.
- Requires **no additional host software** beyond a USB cable.
- Provides a `flash.sh` convenience wrapper so operators need only extract and
  run one script.

## pv-flash-bundle overview

`pv-flash-bundle` (`recipes-bsp/pv-flash/pv-flash-bundle.bb`) assembles a
self-contained factory flash archive. The exact contents differ by machine:

### Verdin iMX8MM (eMMC)

```
pv-flash-bundle-verdin-imx8mm/
  uuu                        — portable UUU binary (patchelf'd for any x86-64 host)
  uuu.auto                   — UUU script: SDP + SDPV boot → fastboot → raw-sparse eMMC flash
  flash.sh                   — decompresses .wic.gz → .wic, then calls sudo ./uuu ./
  imx-boot-recoverytezi      — recovery U-Boot (built via tezi-recovery multiconfig)
  pantavisor-starter-verdin-imx8mm.rootfs.wic.gz   — compressed WIC disk image
  pantavisor-starter-verdin-imx8mm.rootfs.wic.bmap — bmaptool map (if present)
```

### Colibri iMX6ULL (NAND)

```
pv-flash-bundle-colibri-imx6ull/
  uuu                        — portable UUU binary (patchelf'd for any x86-64 host)
  uuu.auto                   — UUU script: SDP boot → fastboot → NAND write + UBI create
  flash.sh                   — calls sudo ./uuu ./
  u-boot.imx-recoverytezi   — recovery U-Boot (built via tezi-recovery multiconfig)
  u-boot.imx-rawnand               — production NAND U-Boot (from tezi-recovery rawnand build)
  pantavisor-starter-colibri-imx6ull.rootfs.ubifs  — UBIFS root filesystem
```

## How the flash sequence works

### Verdin iMX8MM

1. iMX8MM ROM loads recovery U-Boot via SDP + SDPV (two-stage: SPL then full U-Boot).
2. Recovery U-Boot enters fastboot mode (`fastboot usb 0`).
3. `flash.sh` decompresses `.wic.gz` → `.wic`; UUU writes the raw disk image to
   eMMC using `FB: flash -raw2sparse all`.
4. Module resets and boots Pantavisor from eMMC.

### Colibri iMX6ULL

1. iMX6ULL ROM loads recovery U-Boot directly via SDP (single-stage: full U-Boot,
   no SPL overhead).
2. Recovery U-Boot enters fastboot mode.
3. UUU writes U-Boot to NAND `u-boot1` and `u-boot2` partitions (raw byte offsets,
   bypassing partition `ro` flags).
4. UUU erases the `ubi` MTD partition, creates a `boot` UBI volume, and writes
   the UBIFS rootfs to it.
5. Module resets and boots Pantavisor from NAND.

The recovery U-Boot for both machines is built by the `tezi-recovery` multiconfig
(`DISTRO = "tezi"`). The `pv.distroboot.cfg` fragment is excluded from the
tezi-recovery build via
`dynamic-layers/meta-toradex-bsp-common/recipes-bsp/u-boot/u-boot-toradex_%.bbappend`,
so it does not override the `fastboot usb 0` bootcmd.

## Prerequisites

- USB cable (USB-C for Verdin, Micro-USB for most Colibri carrier boards) from
  the board's **USB OTG** port to your host PC.
- Module in **USB serial download (SDP) mode** — see the board-specific page:
  - [boards/verdin-imx8mm.md](boards/verdin-imx8mm.md)
  - [boards/colibri-imx6ull.md](boards/colibri-imx6ull.md)
- An x86-64 Linux host (the bundled `uuu` binary targets x86-64).

## Building

```bash
# Full Toradex starter build (includes pv-flash-bundle for both machines):
kas build kas/build-configs/build-base-toradex-starter.yaml

# Bundle only (set MACHINE appropriately before running):
bitbake pv-flash-bundle
```

Artifacts after a successful build:

```
build/tmp-scarthgap/deploy/images/verdin-imx8mm/pv-flash-bundle-verdin-imx8mm.tar.gz
build/tmp-scarthgap/deploy/images/colibri-imx6ull/pv-flash-bundle-colibri-imx6ull.tar.gz
```

## Flashing procedure

### 1. Put the module into USB download mode

See the board-specific page linked above for how to enter SDP mode on your
carrier board.

### 2. Extract the bundle

```bash
tar xzf pv-flash-bundle-<machine>.tar.gz
cd pv-flash-bundle-<machine>
```

### 3. Flash

```bash
./flash.sh
```

`flash.sh` invokes `sudo ./uuu ./`, which reads `uuu.auto` and executes the full
SDP → fastboot → storage flash sequence. You will be prompted for your sudo
password if needed.

### 4. Boot normally

Power-cycle the board (or release the recovery button/jumper). It will boot
Pantavisor from eMMC (Verdin) or NAND (Colibri).

## Carrier board selection (Verdin iMX8MM)

The build targets the **WiFi variant** with the Development Board device tree
by default. To target a different carrier board, update `UBOOT_DTB_NAME` in
`kas/machines/verdin-imx8mm.yaml`:

| Carrier board | `UBOOT_DTB_NAME` value |
|---|---|
| Development board (default) | `imx8mm-verdin-wifi-dev.dtb` |
| Ivy board | `imx8mm-verdin-wifi-ivy.dtb` |
| Mallow board | `imx8mm-verdin-wifi-mallow.dtb` |
| Yavia board | `imx8mm-verdin-wifi-yavia.dtb` |

## Notes

- **USB permissions**: if you get a permission error or `LIBUSB_ERROR_IO`, two
  udev rules are needed — one for the NXP SDP ROM (VID `15a2`) and one for the
  Toradex fastboot U-Boot (VID `1b67`). The NXP SDP device is misidentified as
  an HID input device by Linux; the rule below prevents `hid_generic` from
  claiming it:
  ```bash
  sudo tee /etc/udev/rules.d/70-nxp-sdp.rules << 'EOF'
  SUBSYSTEM=="usb", ATTRS{idVendor}=="15a2", ATTRS{idProduct}=="0080", ENV{ID_INPUT}="", ENV{LIBINPUT_IGNORE_DEVICE}="1", MODE="0666", TAG+="uaccess"
  EOF
  echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1b67", MODE="0666"' \
      | sudo tee /etc/udev/rules.d/70-toradex-uuu.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```
  Disconnect and reconnect the USB cable after applying the rules.
- **Verdin — wic.gz decompression**: `flash.sh` decompresses `.wic.gz` to a
  temporary `.wic` before invoking `uuu`, then removes it on exit. UUU's
  `FB: flash -raw2sparse` path does not decompress gzip input — passing `.wic.gz`
  directly corrupts the eMMC partition table.
- **Colibri — NAND layout**: The `ubi` MTD partition starts at byte offset
  `0x400000` (`512k(mx6ull-bcb) + 1536k(u-boot1) + 1536k(u-boot2) + 512k(u-boot-env)`).
  U-Boot raw writes use byte offsets to bypass the `ro` flag on `u-boot1`/`u-boot2`.
- **Colibri — UBIFS geometry**: `MKUBIFS_ARGS = "-m 2048 -e 126976 -c 4096"` —
  2KB page size, 126976-byte LEB (128KB block − 2 pages UBI overhead), 4096 max LEBs.
- **Existing installation**: the recovery U-Boot is built with `CONFIG_ENV_IS_NOWHERE=y`,
  so it ignores any stored environment. Flashing works correctly even on modules
  that already have a Pantavisor installation.
