# Flashing: Toradex Colibri iMX6ULL

**Flash method:** UUU via pv-flash-bundle — see [toradex.md](../toradex.md)

**Image artifact:** `pv-flash-bundle-colibri-imx6ull.tar.gz`

## Entering USB serial download (SDP) mode

The Colibri iMX6ULL ROM enters SDP mode when the `RECOVERY#` pin is held low
during power-on. For the iMX6ULL the ROM directly loads a full U-Boot binary
(no SPL stage).

### Colibri Evaluation Board v3

1. Connect a Micro-USB cable from the board's **USB Client** port to your host PC.
2. Hold the **Recovery** button while applying power (or while pressing Reset).
3. Release after ~1 second. The module enumerates as an NXP SDP device.

Verify detection:

```bash
sudo ./uuu -lsusb
# Expected: SE Blank ARIK  or  SDP:MX6ULL
```

### Other carrier boards

Consult the Toradex developer documentation for your specific carrier board.
The general procedure is the same: pull `RECOVERY#` low during power-on.

## NAND partition layout

The production NAND layout (from `colibri-imx6ull_defconfig`):

| Partition | Offset | Size | Purpose |
|---|---|---|---|
| `mx6ull-bcb` | `0x000000` | 512 KB | Boot Control Block |
| `u-boot1` _(ro)_ | `0x080000` | 1536 KB | Primary U-Boot |
| `u-boot2` _(ro)_ | `0x200000` | 1536 KB | U-Boot redundant copy |
| `u-boot-env` | `0x380000` | 512 KB | U-Boot environment |
| `ubi` | `0x400000` | remainder | UBI device (`boot` UBIFS volume) |

The pv-flash-bundle UUU script writes U-Boot to `u-boot1` and `u-boot2` using
raw byte offsets (bypassing the `ro` partition flag, which only applies in Linux
userspace). The `boot` UBI volume holds the Pantavisor UBIFS rootfs.

## Flashing

With the module in SDP mode, follow the procedure in
[toradex.md — Flashing procedure](../toradex.md#flashing-procedure).

## Notes

- WiFi firmware is included (`linux-firmware-sd8997`).
- eMMC-equipped Colibri iMX6ULL modules (product ID 0062) use a different machine
  configuration (`colibri-imx6ull-emmc`) and are not covered by this build.
- After flashing, release the recovery button/jumper before the next power cycle
  so the module boots from NAND.
