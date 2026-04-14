# Flashing via Toradex Easy Installer (Tezi)

Toradex boards use the **Toradex Easy Installer (Tezi)** to flash images to
the on-module eMMC over USB. Pantavisor produces a custom `pv_teziimg` bundle
that is compatible with the Tezi protocol.

## Machines using this method

| Machine file | Board |
|---|---|
| `kas/machines/colibri-imx6ull.yaml` | Toradex Colibri iMX6ULL |
| `kas/machines/verdin-imx8mm.yaml` | Toradex Verdin iMX8MM (WiFi variant) |

For board-specific hardware setup (boot switches, recovery mode) see:

- [Colibri iMX6ULL](boards/colibri-imx6ull.md)
- [Verdin iMX8MM](boards/verdin-imx8mm.md)

## Prerequisites

- USB Type-A to Micro-USB or USB-C cable (depends on carrier board)
- Host PC with Tezi running, **or** use the Tezi USB recovery mode
- [Toradex Easy Installer](https://developer.toradex.com/easy-installer/toradex-easy-installer/) installed on the host

## Locating the image

After a successful build the Tezi bundle is at:

```
build/tmp-scarthgap/deploy/images/<machine>/pantavisor-starter-<machine>*pv_teziimg.tar.xz
```

## Flashing procedure

### 1. Put the module into recovery mode

Each carrier board has a different way to enter Tezi recovery mode. See the
board-specific page linked above.

### 2. Open Toradex Easy Installer on the host

Tezi detects the module automatically over USB when it is in recovery mode.

### 3. Load the Pantavisor bundle

In the Tezi UI:

1. Click **Upload Image**
2. Select the `*pv_teziimg.tar.xz` file
3. Tezi extracts and lists the image

Alternatively, place the `.tar.xz` in a directory served by a local HTTP
server and point Tezi at that URL.

### 4. Flash

Select the Pantavisor image in the Tezi UI and click **Install**. Tezi writes
the image to eMMC and reboots the module automatically.

## Notes

- The `pv_teziimg` format is a Pantavisor-specific extension of the standard
  Tezi image format. It includes the Pantavisor initramfs and boot files
  in addition to the rootfs.
- The Verdin iMX8MM build uses the WiFi device tree
  (`imx8mm-verdin-wifi-dev.dtb`) by default. Change `UBOOT_DTB_NAME` in
  `kas/machines/verdin-imx8mm.yaml` to target a different carrier board.
- The Colibri iMX6ULL build includes carrier-board-specific settings from
  `conf/machine/include/colibri-imx6ull.inc`.
