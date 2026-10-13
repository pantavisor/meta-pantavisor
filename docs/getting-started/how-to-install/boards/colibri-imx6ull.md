# Flashing: Toradex Colibri iMX6ULL

**Flash method:** UUU via pv-flash-bundle — see [toradex.md](../toradex.md)

**Image artifact:** `pv-flash-bundle-colibri-imx6ull.tar.gz`

**Build:** `kas build kas/build-configs/release/colibri-imx6ull-scarthgap.yaml` — see the
[build config table](/meta-pantavisor/overview/build-system#build-configs).

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

The layout below is set in one place, `PV_UBOOT_MTDPARTS` in
`kas/machines/colibri-imx6ull.yaml` (mirrored in the release build-config). It is
given to U-Boot through `oemEnv.txt` (as its `mtdparts`), to the kernel through
`PV_BOOT_OEMARGS`, and to the flashing U-Boot by the UUU script, so all three
agree:

```
512k(mx6ull-bcb),1536k(u-boot1)ro,1536k(u-boot2)ro,512k(u-boot-env),32m(fitA),32m(fitB),-(ubi)
```

| Partition | Offset | Size | Purpose |
|---|---|---|---|
| `mx6ull-bcb` | `0x000000` | 512 KB | Boot Control Block |
| `u-boot1` _(ro)_ | `0x080000` | 1536 KB | Primary U-Boot |
| `u-boot2` _(ro)_ | `0x200000` | 1536 KB | U-Boot redundant copy |
| `u-boot-env` | `0x380000` | 512 KB | U-Boot environment (also holds the A/B state) |
| `fitA` | `0x400000` | 32 MB | BSP FIT slot A (raw, no filesystem) |
| `fitB` | `0x2400000` | 32 MB | BSP FIT slot B (raw, no filesystem) |
| `ubi` | `0x4400000` | remainder | UBI device (`boot` UBIFS volume) |

The pv-flash-bundle UUU script writes U-Boot to `u-boot1` and `u-boot2` using
raw byte offsets (bypassing the `ro` partition flag, which only applies in Linux
userspace). The `boot` UBI volume holds the Pantavisor UBIFS rootfs.

The script also **erases the `u-boot-env` partition** so U-Boot starts from its
built-in default environment. A leftover env from a prior image (e.g. Toradex
Easy Installer / TorizonCore) carries a stale `bootcmd` that looks for a UBI
`bootscr` volume and fails with `Volume bootscr not found!`.

Check the table on a running board:

```bash
cat /proc/mtd
# "u-boot-env", "fitA", "fitB" and "ubi" must be listed, in that order
```

## Boot flow

Unlike Toradex's stock `ubiboot` (which expects raw `kernel`/`dtb`/`rootfs` UBI
volumes), this build keeps a single UBIFS `boot` volume holding the whole
Pantavisor rootfs. The default `bootcmd` (baked in via
`recipes-bsp/u-boot/files/pv.colibri-imx6ull.cfg`) mounts that volume and sources
the Pantavisor boot script from it:

```
ubi part ubi && ubifsmount ubi0:boot && setenv devtype ubi && \
    ubifsload ${scriptaddr} /boot/boot.scr && source ${scriptaddr}
```

The machine enables the `pv-uboot-ab` feature, so `boot.scr` is built from
`boot.cmd.pvab` (see [A/B boot](#ab-boot-pv-uboot-ab)). Without the feature it
is the generic `boot.cmd.pvgeneric`, which pulls the FIT from
`/trails/<rev>/bsp/` on the UBIFS volume. Either way the kernel then attaches UBI
and Pantavisor mounts its storage from `ubi0:boot`. The kernel command line is
driven by `PV_BOOT_OEMARGS` -> `oemEnv.txt` -> `${oemargs}`:

```
mtdparts=gpmi-nand:512k(mx6ull-bcb),1536k(u-boot1)ro,1536k(u-boot2)ro,512k(u-boot-env),32m(fitA),32m(fitB),-(ubi) ubi.mtd=ubi pv_storage.device=ubi0:boot pv_storage.fstype=ubifs
```

The `mtdparts=` entry is **required**: the colibri-imx6ull device tree declares
no NAND partitions, so without it the kernel has no partition named `ubi` and
`ubi.mtd=ubi` cannot attach (Pantavisor then fails to resolve `ubi0:boot`).
Toradex's stock boot supplies the same `mtdparts` via its `setup` env; the
Pantavisor boot script bypasses that, so it is carried here instead.

### A/B boot (pv-uboot-ab)

With `PANTAVISOR_FEATURES:append = " pv-uboot-ab"` (on by default for this
machine) the BSP FIT is not read from UBIFS but from the raw partitions `fitA`
and `fitB`. Each starts with a 4 KiB text header, then the FIT at offset
`0x1000`:

```
fit_rev=<revision>
fit_size=<bytes>
<NUL padding to 4096>
<FIT image>
```

`boot.cmd.pvab` (`recipes-bsp/u-boot/files/boot.cmd.pvab`) does, in order:

1. Reads `pv_rev`, `pv_try`, `pv_trying` from U-Boot's own environment (the
   `u-boot-env` partition); `pv_rev` unset means revision `0` and is saved once, so Pantavisor has an environment to edit in place. A `pv_try`
   that was already attempted (`pv_trying == pv_try`) means the try failed, so
   the checkpoint `pv_rev` boots and `pv_trying` is cleared; a fresh `pv_try`
   is booted and recorded in `pv_trying`. `saveenv` runs only when that state
   changes, and a failed `saveenv` does not stop the boot.
2. Imports `/oemEnv.txt` from UBIFS (`oemargs`, `mtdparts`, default carrier).
3. Reads the header of `fitA` and `fitB` and picks the partition whose
   `fit_rev` equals the revision to boot. No partition holds the try revision:
   the checkpoint revision boots instead. None holds `pv_rev`: `fitA` boots and
   the console says so.
4. Loads header and FIT in one `nand read` from the partition start (bad blocks are skipped the same way Pantavisor's writer skips them; the FIT is at `+0x1000` in that stream) and `bootm`s the
   configuration named after `fdtfile`, with `pv_rev`, `pv_try`,
   `PV_BOOTLOADER_TYPE=uboot-ab` and `PV_BOOTLOADER_TRYING_ENV=mtd:u-boot-env` on
   the kernel command line.

Pantavisor writes an update's FIT into the inactive partition and sets
`pv_try` in the same U-Boot environment; on a good boot it commits `pv_rev`.
Inspect the state on the U-Boot console:

```
printenv pv_rev pv_try pv_trying
nand read ${loadaddr} fitA 0x1000 && md.b ${loadaddr} 40
```

### FIT image

The kernel, the Pantavisor initramfs and **all** Colibri iMX6ULL device trees are
packed into one FIT, `bsp/pantavisor.fit`, instead of separate kernel/initrd/dtb
files, so one image serves every module variant and carrier. The machine config
(`kas/machines/colibri-imx6ull.yaml`) switches this on:

```bitbake
KERNEL_CLASSES:append:colibri-imx6ull = " kernel-fitimage"
KERNEL_IMAGETYPE:colibri-imx6ull = "fitImage"
```

Each device tree is a configuration named `conf-<dtb file name>`, for example
`conf-imx6ull-colibri-wifi-aster.dtb`. The boot script boots the configuration
named after U-Boot's `fdtfile` (see [carrier selection](#carrier-board-and-device-tree)),
and falls back to the FIT's default configuration
(`FIT_CONF_DEFAULT_DTB`, the Aster WiFi tree) if that name is not in the FIT.

After a build, list what went in:

```bash
mkimage -l build/tmp-*/deploy/images/colibri-imx6ull/fitImage-pantavisor-initramfs-colibri-imx6ull--*.bin | grep -E "Default Configuration|Configuration [0-9]"
```

On the board, the boot script runs `iminfo` on the loaded FIT, so the console
log shows the same listing (`CONFIG_CMD_IMI` is enabled in
`pv.colibri-imx6ull.cfg`).

> **Note:** U-Boot's UBIFS driver is read-only. Without `pv-uboot-ab` the
> try-boot/rollback state (`pv.env`) is therefore not persisted on NAND; the
> generic boot script skips the `save` step on UBI. With `pv-uboot-ab` the state
> lives in U-Boot's environment and is persisted.

## Carrier board and device tree

The Colibri iMX6ULL **WB** modules carry a Marvell 88W8997 (SD8997) WiFi/BT chip
on the second SD/MMC controller (`usdhc2`). That interface is only enabled by the
`imx6ull-colibri-wifi-*` device trees; the plain `imx6ull-colibri-*` DTBs are the
non-wireless SKU and leave `usdhc2` disabled. With the wrong DTB the kernel never
probes the chip: `mwifiex_sdio` loads but binds nothing and no `wlan0` appears.

The FIT carries every tree and the board picks its own. Toradex's U-Boot builds

```
fdtfile = imx6ull-colibri${variant}-${fdt_board}.dtb
```

`variant` (for example `-wifi`) is read from the module's config block at
runtime, so module variants need no setting. `fdt_board` names the carrier and
**cannot be detected**; Toradex's default is `eval-v3`. The Pantavisor boot
scripts therefore take a build-time default carrier:

```bitbake
PV_UBOOT_DEFAULT_FDT_BOARD = "aster"     # kas/machines/colibri-imx6ull.yaml
```

It is written to `oemEnv.txt` as `pv_default_fdt_board=aster`. The boot script
applies it only while `fdt_board` is empty or still the stock `eval-v3`. A
`fdt_board` you saved in the environment wins. On every boot the script then
rebuilds `fdtfile` from `variant` and `fdt_board` and logs it, e.g.
`carrier aster: fdtfile imx6ull-colibri-wifi-aster.dtb`.

| Carrier | `fdt_board` | Tree on a WiFi module |
|---|---|---|
| Aster | `aster` | `imx6ull-colibri-wifi-aster.dtb` |
| Evaluation Board v3 | `eval-v3` | `imx6ull-colibri-wifi-eval-v3.dtb` |
| Iris | `iris` | `imx6ull-colibri-wifi-iris.dtb` |
| Iris v2 | `iris-v2` | `imx6ull-colibri-wifi-iris-v2.dtb` |

To change the carrier of one board (U-Boot console, interrupt autoboot):

```
setenv fdt_board iris
saveenv
```

`variant` is set at runtime, so the module needs no setting. The Evaluation Board v3 is the stock
value and so follows the build default: to default a whole build to it, set
`PV_UBOOT_DEFAULT_FDT_BOARD = "eval-v3"` (or empty to turn the default off) in the
machine config and its mirror in the release build-config. A different
`oemEnv.txt` on the UBIFS volume (`/oemEnv.txt`) changes it for one device.

Check the result after a build and on the board:

```bash
mkimage -l build/tmp-*/deploy/images/colibri-imx6ull/fitImage-pantavisor-initramfs-colibri-imx6ull--*.bin \
  | grep -E 'Default Configuration|Configuration [0-9]'
# Expected: Default Configuration: 'conf-imx6ull-colibri-wifi-aster.dtb' and one
#           Configuration per carrier/variant tree
```

On the running board, `cat /sys/firmware/devicetree/base/model` reflects the
active tree and `usdhc2`/`mmc1` plus a `wlan0` interface should appear once a
WiFi tree is booted. `PV_INITIAL_DTB` and `PV_UBOOT_AUTOFDT` do not matter for
the FIT: `pantavisor-bsp.bb` only reads them on the discrete-image path.

## Flashing

With the module in SDP mode, follow the procedure in
[toradex.md — Flashing procedure](../toradex.md#flashing-procedure).

With `pv-uboot-ab` the bundle also contains `fitA.img` (the revision 0 header
plus `pantavisor.fit`). The UUU script sets the layout above in the flashing
U-Boot, erases `u-boot-env`, erases and writes `fitA` (`nand write.trimffs`,
skipping bad blocks), erases `fitB`, then erases `ubi` and writes the UBIFS.
Check the header before flashing:

```bash
head -c 64 fitA.img | tr '\0' ' '
# fit_rev=0 fit_size=<bytes>
```

## Notes

- WiFi firmware is included (`linux-firmware-sd8997`).
- eMMC-equipped Colibri iMX6ULL modules (product ID 0062) use a different machine
  configuration (`colibri-imx6ull-emmc`) and are not covered by this build.
- After flashing, release the recovery button/jumper before the next power cycle
  so the module boots from NAND.
