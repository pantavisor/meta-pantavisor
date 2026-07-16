# Flashing: Toradex Verdin iMX8M Mini

**Flash method:** UUU via pv-flash-bundle — see [toradex.md](../toradex.md)

**Image artifact:** `pv-flash-bundle-verdin-imx8mm.tar.gz`

> This board no longer flashes via Toradex Easy Installer (Tezi). If you have
> older instructions or a `pv_teziimg.tar.xz` bundle, they are outdated.

## Supported carrier boards and device trees

The default build targets the **WiFi variant** with the development carrier
board device tree. Change `UBOOT_DTB_NAME` in `kas/machines/verdin-imx8mm.yaml`
to match your carrier board:

| Carrier board | `UBOOT_DTB_NAME` value |
|---|---|
| Development board (default) | `imx8mm-verdin-wifi-dev.dtb` |
| Ivy board | `imx8mm-verdin-wifi-ivy.dtb` |
| Mallow board | `imx8mm-verdin-wifi-mallow.dtb` |
| Yavia board | `imx8mm-verdin-wifi-yavia.dtb` |

## Entering USB serial download (SDP) mode

The Verdin SOM enters SDP mode when the `RECOVERY#` signal is held low during
power-on. The exact mechanism depends on the carrier board.

### Verdin Development Board

1. Connect a USB-C cable from the board's **USB-C (OTG)** port to your host PC.
2. Hold the **Recovery** button while applying power (or while pressing Reset).
3. Release the button after ~1 second. The module enumerates on the host as
   an NXP SDP device (`ID 1fc9:0146`).

Verify detection:

```bash
sudo ./uuu -lsusb
# Expected: SE Blank ARIK  or  SDP:MX8MM
```

### Other carrier boards

The general procedure is the same: pull `RECOVERY#` low during power-on.
Consult the Toradex developer documentation for your specific carrier board.

## Flashing

Follow the [pv-flash-bundle procedure](../toradex.md): extract the bundle and
run `./flash.sh`. UUU boots the recovery U-Boot (SDP then SDPV), jumps to
fastboot, and writes the disk image directly to eMMC via
`FB: flash -raw2sparse all`.

## Notes

- WiFi is enabled (`TORADEX_VARIANT = "wifi"`); `cfg80211` and `mwifiex_sdio`
  are autoloaded.
- `PV_UBOOT_AUTOFDT = "1"` is set; the runtime DTB is pinned by `UBOOT_DTB_NAME`.
  If you switch carrier boards, update `UBOOT_DTB_NAME` in the machine YAML
  before building.
- eMMC (MMC0) is the primary storage. The pv-flash-bundle writes to it directly
  via UUU raw-sparse flash. `flash.sh` decompresses the bundled `.wic.gz` to a
  temporary `.wic` before invoking `uuu`, since UUU's `-raw2sparse` path does
  not accept gzip input directly.
