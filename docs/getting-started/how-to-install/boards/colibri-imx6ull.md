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

The script also **erases the `u-boot-env` partition** so U-Boot starts from its
built-in default environment. A leftover env from a prior image (e.g. Toradex
Easy Installer / TorizonCore) carries a stale `bootcmd` that looks for a UBI
`bootscr` volume and fails with `Volume bootscr not found!`.

## Boot flow

Unlike Toradex's stock `ubiboot` (which expects raw `kernel`/`dtb`/`rootfs` UBI
volumes), this build keeps a single UBIFS `boot` volume holding the whole
Pantavisor rootfs. The default `bootcmd` (baked in via
`recipes-bsp/u-boot/files/pv.colibri-imx6ull.cfg`) mounts that volume and sources
the generic Pantavisor boot script from it:

```
ubi part ubi && ubifsmount ubi0:boot && setenv devtype ubi && \
    ubifsload ${scriptaddr} /boot/boot.scr && source ${scriptaddr}
```

`boot.cmd.pvgeneric` detects `devtype=ubi` and uses `ubifsload` to pull the
Pantavisor FIT (kernel + initramfs + dtb) from `/trails/<rev>/bsp/`. The kernel
then attaches UBI and Pantavisor mounts its storage from `ubi0:boot`. All of
this is driven by `PV_BOOT_OEMARGS` → `oemEnv.txt` → `${oemargs}`:

```
mtdparts=gpmi-nand:512k(mx6ull-bcb),1536k(u-boot1)ro,1536k(u-boot2)ro,512k(u-boot-env),-(ubi) ubi.mtd=ubi pv_storage.device=ubi0:boot pv_storage.fstype=ubifs
```

The `mtdparts=` entry is **required**: the colibri-imx6ull device tree declares
no NAND partitions, so without it the kernel has no partition named `ubi` and
`ubi.mtd=ubi` cannot attach (Pantavisor then fails to resolve `ubi0:boot`).
Toradex's stock boot supplies the same `mtdparts` via its `setup` env; the
Pantavisor boot script bypasses that, so it is carried here instead.

> **Note:** U-Boot's UBIFS driver is read-only, so the try-boot/rollback state
> (`pv.env`) is not persisted across reboots on NAND; the boot script skips the
> `save` step when booting from UBI.

## WiFi / Bluetooth device tree (FDT selection)

The Colibri iMX6ULL **WB** modules carry a Marvell 88W8997 (SD8997) WiFi/BT chip
on the second SD/MMC controller (`usdhc2`). That interface is only enabled by the
`imx6ull-colibri-wifi-*` device trees; the plain `imx6ull-colibri-*` DTBs are the
non-wireless SKU and leave `usdhc2` disabled. With the wrong DTB the kernel never
probes the chip — `mwifiex_sdio` loads but binds nothing and no `wlan0` appears.

Which DTB Pantavisor boots is decided at image-build time and baked into the BSP
`run.json` (`"fdt": ...`). The Toradex platform sets `PV_UBOOT_AUTOFDT = "1"`,
which makes `pantavisor-bsp.bb` pick the **first** entry of `KERNEL_DEVICETREE`.
For colibri-imx6ull that list starts with the non-WiFi `imx6ull-colibri-aster.dtb`,
so autofdt would always select the wireless-less tree. To boot the WiFi DTB the
machine config (`kas/machines/colibri-imx6ull.yaml`, mirrored in the release
build-config) pins it explicitly and disables autofdt:

```bitbake
PV_INITIAL_DTB = "imx6ull-colibri-wifi-aster.dtb"
PV_UBOOT_AUTOFDT:colibri-imx6ull = ""
MACHINE_FEATURES:append = " wifi"
```

Two subtleties matter here:

- **Disabling autofdt is required.** If `PV_UBOOT_AUTOFDT` stays `"1"`, both the
  `PV_INITIAL_DTB` branch and the autofdt branch run, and the autofdt branch
  writes its `"fdt"` key *last* — silently overriding `PV_INITIAL_DTB` with the
  first (non-WiFi) `KERNEL_DEVICETREE` entry.
- **Use the `:colibri-imx6ull` machine override, not a plain `=`.** kas emits the
  `platform-toradex` block (`PV_UBOOT_AUTOFDT = "1"`) *after* the machine block in
  `local.conf`, so a plain `PV_UBOOT_AUTOFDT = ""` loses to it (last plain `=`
  wins). The machine override is applied at BitBake finalize time, after all plain
  assignments, so it reliably wins.

Pick the DTB that matches your carrier board:

| Carrier | WiFi DTB |
|---|---|
| Aster | `imx6ull-colibri-wifi-aster.dtb` |
| Evaluation Board v3 | `imx6ull-colibri-wifi-eval-v3.dtb` |
| Iris | `imx6ull-colibri-wifi-iris.dtb` |
| Iris v2 | `imx6ull-colibri-wifi-iris-v2.dtb` |

After building, confirm the BSP selected the WiFi tree before flashing:

```bash
grep -o '"fdt":"[^"]*"' \
  build/*/work/cortexa7t2hf-neon-poky-linux-musleabi/pantavisor-bsp/1.0/pvbspstate/bsp/run.json
# Expected: "fdt":"imx6ull-colibri-wifi-aster.dtb"
# A "nxp/imx/..." prefix means autofdt is still winning (non-WiFi tree selected).
```

On the running board, `cat /sys/firmware/devicetree/base/model` reflects the
active tree and `usdhc2`/`mmc1` plus a `wlan0` interface should appear once the
WiFi DTB is booted.

## Flashing

With the module in SDP mode, follow the procedure in
[toradex.md — Flashing procedure](../toradex.md#flashing-procedure).

## Notes

- WiFi firmware is included (`linux-firmware-sd8997`).
- eMMC-equipped Colibri iMX6ULL modules (product ID 0062) use a different machine
  configuration (`colibri-imx6ull-emmc`) and are not covered by this build.
- After flashing, release the recovery button/jumper before the next power cycle
  so the module boots from NAND.
