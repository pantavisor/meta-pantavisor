---
sidebar_position: 17
---
# USB factory-flash bundle

`pv-flash-bundle` (`recipes-bsp/pv-flash/pv-flash-bundle.bb`) is meta-pantavisor's
**preferred way to flash devices that program their on-board storage over USB**
instead of via a plain `.wic` write — NXP i.MX boards through NXP's UUU tool, and
Rockchip boards through `rkdeveloptool`. It bundles the image payload, the host
flashing tool as a portable binary, a boot/recovery loader, and generated flash
scripts into a single `pv-flash-bundle-${MACHINE}.tar.gz`, so flashing needs
nothing beyond a USB cable and the extracted archive.

Every currently supported board in [Getting Started](../getting-started/how-to-install/index.md)
that flash-over-USB uses this recipe:

- **Toradex** — [Verdin iMX8MM](../getting-started/how-to-install/boards/verdin-imx8mm.md) and
  [Colibri iMX6ULL](../getting-started/how-to-install/boards/colibri-imx6ull.md); see
  [Flashing Toradex Modules](../getting-started/how-to-install/toradex.md) for the end-user procedure.
- **Variscite** — [DART-MX8M-MINI](../getting-started/how-to-install/boards/imx8mm-var-dart.md) and
  [VAR-SOM-MX8M-NANO](../getting-started/how-to-install/boards/imx8mn-var-som.md); see
  [Flashing via NXP uuu](../getting-started/how-to-install/uuu.md) for the end-user procedure.
- **NXP i.MX8QXP MEK** — [Board Guide](../getting-started/how-to-install/boards/imx8qxp-b0-mek.md); also
  covered by [Flashing via NXP uuu](../getting-started/how-to-install/uuu.md).
- **Rockchip** — [Orange Pi 5B](../getting-started/how-to-install/boards/orangepi-5b.md) (RK3588S); see
  [Flashing Rockchip devices](../getting-started/how-to-install/rockchip.md) for the end-user procedure.

This page covers how the recipe itself is built and how to wire up a new
machine.

## Design

The recipe has no compile step — `do_configure` and `do_compile` are
`noexec`. All the work happens in a single `do_deploy` task that copies
pre-built artifacts into a bundle directory, expands two `.in` script
templates, and tars the result.

Everything machine-specific is expressed as `PV_FLASH_*` variables, set per
machine in `kas/machines/<machine>.yaml` (`local_conf_header`) or in the
release build-config (`kas/build-configs/release/<machine>-scarthgap.yaml`).
The recipe itself never mentions a machine name — adding a new board is a
matter of setting variables and dropping in templates, not editing the `.bb`.

| Variable | Role | Default |
|---|---|---|
| `PV_FLASH_IMAGE` | Image recipe whose rootfs goes into the bundle | `pantavisor-starter` |
| `PV_FLASH_TOOL` | Host flashing tool bundled and driven by `flash.sh`: `uuu` (NXP SDP/fastboot) or `rkdeveloptool` (Rockchip Maskrom) | `uuu` *(set to `rkdeveloptool` for `orangepi-5b`)* |
| `PV_FLASH_RK_LOADER` | `rkdeveloptool` only: glob for the Rockchip USB loader (DDR init + miniloader/usbplug) in the **main build's** `DEPLOY_DIR_IMAGE`; installed into the bundle as `loader.bin` and passed to `rkdeveloptool db` | *(none, set for `orangepi-5b`)* |
| `PV_FLASH_RECOVERY_MC` | Multiconfig that builds the recovery U-Boot | *(none)* |
| `PV_FLASH_RECOVERY_RECIPE` | Recipe to build in that multiconfig (e.g. `u-boot-toradex`) | *(none)* |
| `PV_FLASH_RECOVERY_IMAGE` | Filename of the recovery U-Boot in the recovery MC's deploy dir | *(none)* |
| `PV_FLASH_BOOT_IMAGE` | Glob for a boot binary sourced directly from the **main build's** `DEPLOY_DIR_IMAGE` — for machines whose production bootloader already self-enters SDP/fastboot download mode | *(none, set for `imx8mm-var-dart`/`imx8mn-var-som`/`imx8qxp-b0-mek`)* |
| `PV_FLASH_NAND_UBOOT` | Production NAND U-Boot filename (NAND machines only) | *(none, set for `colibri-imx6ull`)* |
| `PV_FLASH_UBIFS` | UBIFS rootfs filename (NAND machines only) | *(none, set for `colibri-imx6ull`)* |
| `PV_FLASH_UUU_SCRIPT_IN` | `file://uuu.auto.in` template SRC_URI entry | *(none)* |
| `PV_FLASH_FLASH_SCRIPT_IN` | `file://flash.sh.in` template SRC_URI entry | *(none)* |
| `PV_FLASH_README_IN` | `file://README.md.in` template SRC_URI entry — an optional `README.md` shipped inside the bundle (host prerequisites, OS constraints) | *(none, set for `orangepi-5b`)* |

Leaving `PV_FLASH_UBIFS`/`PV_FLASH_NAND_UBOOT` empty (the eMMC default) makes
`do_deploy` bundle whichever compressed WIC image the main build produced —
`.wic.zst` and/or `.wic.gz` (+ `.wic.bmap` if present) — instead of a raw
UBIFS image.

## `do_deploy` steps

1. **Rootfs artifact** — installs `${PV_FLASH_IMAGE}-${MACHINE}.rootfs.ubifs`
   if `PV_FLASH_UBIFS` is set, otherwise whichever of `.wic.zst` / `.wic.gz`
   is present in `DEPLOY_DIR_IMAGE` (+ `.wic.bmap`); both are installed if
   both exist, and the uncompressed `.wic` is used as a fallback when the main
   build produced no compressed variant.
2. **Recovery U-Boot** — installs `PV_FLASH_RECOVERY_IMAGE` from
   `RECOVERY_DEPLOY_DIR_IMAGE` (`tmp-${DISTRO_CODENAME}-${PV_FLASH_RECOVERY_MC}/deploy/images/${MACHINE}`),
   pulled in via `do_deploy[mcdepends]` on
   `mc::${PV_FLASH_RECOVERY_MC}:${PV_FLASH_RECOVERY_RECIPE}:do_deploy` — only
   added if that multiconfig is actually listed in `BBMULTICONFIG`.
3. **NAND U-Boot** — installs `PV_FLASH_NAND_UBOOT` from the same recovery
   deploy dir, if set.
4. **Boot image from the main build** — if `PV_FLASH_BOOT_IMAGE` is set,
   globs it out of `${DEPLOY_DIR_IMAGE}` (the machine's own build, not a
   recovery MC) and installs it into the bundle as the fixed name
   `imx-boot.bin`. No `mcdepends` needed here: the boot binary is guaranteed
   present already, since `${PV_FLASH_IMAGE}:do_image_complete` (in
   `do_deploy[depends]`) transitively requires the WKS's bootloader partition
   to be built first.
5. **Flashing tool** — for `PV_FLASH_TOOL = "uuu"` (default), copies `uuu` from
   `uuu-native:do_populate_sysroot`; for `PV_FLASH_TOOL = "rkdeveloptool"`, copies
   `rkdeveloptool` from `rkdeveloptool-native:do_populate_sysroot` **and** globs
   `PV_FLASH_RK_LOADER` out of `${DEPLOY_DIR_IMAGE}` into the bundle as the fixed
   name `loader.bin` (`do_deploy[depends]` on `virtual/bootloader:do_deploy`
   guarantees the loader is present). Either way, `patchelf
   --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath ""` is run on the
   copied binary so it runs on an arbitrary x86-64 Linux host regardless of its
   build sysroot. The `rkdeveloptool` build links `libusb-1.0` dynamically, so the
   flashing host must have that library installed.
6. **Script generation** — `sed`-expands `@WIC@ @WIC_GZ@ @WIC_ZST@ @UBIFS@ @UBOOT_NAND@ @RECOVERY_IMAGE@`
   in `uuu.auto.in` and `flash.sh.in` (staged via `FILESEXTRAPATHS:prepend`
   from `files/${MACHINE}/`) into `uuu.auto` and `flash.sh` in the bundle.
   `imx-boot.bin` (step 4) and `loader.bin` (step 5) are referenced as literal
   filenames in those templates instead, since their bundle names are fixed by
   the recipe rather than expanded from a variable. If `PV_FLASH_README_IN` is
   set, `README.md.in` is expanded the same way into `README.md` in the bundle.
   Every `flash.sh.in` resolves the tool at run time — `$UUU` / `$RKDEVELOPTOOL`
   if set, else the bundled `./uuu` / `./rkdeveloptool`, else the tool on
   `PATH` — and prefixes `sudo` only when not already root, so a bundle can
   also be driven from a container or host that ships its own tool (see
   [Flashing via NXP uuu](../getting-started/how-to-install/uuu.md#notes) and
   [Flashing Rockchip devices](../getting-started/how-to-install/rockchip.md#notes)).
7. **Package** — tars the bundle directory as
   `${PN}-${MACHINE}.tar.gz` and symlinks `${PN}-${MACHINE}-latest.tar.gz`.

## Per-machine templates

Machine-specific flashing logic lives entirely in `files/<machine>/uuu.auto.in`
(UUU machines) and `files/<machine>/flash.sh.in` — the recipe code is identical
for every machine.

- **verdin-imx8mm** (eMMC): SDP boot of the recovery U-Boot (SPL then full
  image, VID/PID `0x1b67:0x4fff`), jump to fastboot (`0x1b67:0x4000`), then
  `FB: flash -raw2sparse all @WIC@` writes the disk image directly to eMMC.
  `flash.sh.in` decompresses `@WIC_GZ@` to `@WIC@` first, since UUU's
  `-raw2sparse` path does not accept gzip input.
- **colibri-imx6ull** (NAND): single-stage SDP boot (no SPL), fastboot mode,
  then the recovery U-Boot is written raw to the `u-boot1`/`u-boot2` NAND
  offsets (bypassing the production `ro` MTD flag), the `u-boot-env`
  partition is erased so a stale environment can't override the new build's
  `bootcmd`, and finally the `ubi` partition is erased, a `boot` UBI volume
  created, and the UBIFS rootfs written into it.
- **imx8mm-var-dart** / **imx8mn-var-som** (eMMC, Variscite): SDP boot of the
  *production* `imx-boot.bin` (no recovery build — see below), SPL then full
  U-Boot via `SDPV: write -skipspl` + `jump`, then
  `FB: flash -raw2sparse all @WIC@`. No `CFG:` VID/PID overrides: unlike
  Toradex, Variscite doesn't rebrand the fastboot USB IDs away from NXP's
  defaults, so `uuu` auto-detects the device. Mirrors NXP mfgtools' built-in
  `emmc_all` script, minus its `bootloader`/`mmc partconf` steps — Variscite's
  WKS (`wic/imx-imx-boot-singlepart.wks.in`) already embeds `imx-boot` as a
  raw-offset region inside the `.wic` itself, so flashing the whole `.wic`
  already writes the bootloader; there's no separate eMMC boot-partition
  switch to make. `flash.sh.in` decompresses `@WIC_ZST@` (via `zstd`) to
  `@WIC@` if present, falling back to `@WIC_GZ@` (via `zcat`) otherwise —
  whichever compression `IMAGE_FSTYPES` actually produced for the main build.
- **imx8qxp-b0-mek** (eMMC, NXP eval board): a single `SDPS: boot -scanterm`
  command instead of `SDP:`/`SDPV:` — i.MX8QXP/8QM silicon's ROM supports
  "stream" SDP mode, where the SCU loads the whole boot container (SCFW +
  ATF + OP-TEE + U-Boot) in one transfer with no separate SPL-jump step to
  script. Then the same `FB: flash -raw2sparse all @WIC@` as the other eMMC
  machines. `mmc dev 0` targets eMMC on this board: `usdhc1` (`mmc-hs400-1_8v`
  — an eMMC-only speed mode) probes before `usdhc2` (`sd-uhs-sdr104` — SD
  card), and no `/aliases` override reorders them, so `usdhc1` gets U-Boot
  device index 0.
- **orangepi-5b** (eMMC, Rockchip RK3588S — `PV_FLASH_TOOL = "rkdeveloptool"`):
  no `uuu.auto.in`. `flash.sh.in` waits for a device in USB **Maskrom** mode
  (`rkdeveloptool ld | grep -i maskrom`), sends the loader to SoC SRAM
  (`rkdeveloptool db loader.bin`), streams the whole disk image to eMMC
  (`rkdeveloptool wl 0 @WIC@` — sector 0, so the GPT, idbloader, U-Boot and
  rootfs are all written), then `rkdeveloptool rd` reboots. `loader.bin` is the
  JeffyCN `u-boot-rockchip.bb` `loader.bin` (the Rockchip Miniloader, which also
  provides the `usbplug` that handles `wl`). `flash.sh.in` decompresses
  `@WIC_ZST@`/`@WIC_GZ@` to `@WIC@` first if the main build compressed it.

### Why Variscite and the MEK don't need a recovery multiconfig

Toradex needs `PV_FLASH_RECOVERY_MC` because `recipes-bsp/u-boot/u-boot%.bbappend`
force-overrides `CONFIG_BOOTCOMMAND="run distro_bootcmd"` on every U-Boot
build in the layer, and Toradex's SDP→fastboot entry is driven by that same
`bootcmd`. Variscite's `u-boot-variscite` and the MEK's `u-boot-imx` recipes
get the same override, but their fastboot entry doesn't depend on it: both
`uboot-imx` forks' SPL (`board/variscite/imx8mm_var_dart/spl.c`,
`configs/imx8qxp_mek_defconfig`) build with `CONFIG_SPL_USB_SDP_SUPPORT=y`,
so the ROM/SPL-level SDP-to-fastboot handoff happens before `bootcmd` is
ever evaluated — confirmed by Variscite's own `var-uuu-installer` recipe (in
`meta-variscite-bsp-imx`), which bundles the *same* production build's
`imx-boot`/`.wic`/`.bmap` with no separate recovery step. `PV_FLASH_BOOT_IMAGE`
exists for exactly this case: pull the boot binary straight from the main
build instead of standing up a second multiconfig.

See [Flashing Toradex Modules](../getting-started/how-to-install/toradex.md#how-the-flash-sequence-works),
[Flashing via NXP uuu](../getting-started/how-to-install/uuu.md), and
[Flashing Rockchip devices](../getting-started/how-to-install/rockchip.md) for the full
step-by-step sequences and hardware-specific notes (NAND geometry, udev rules,
boot-mode switches, Maskrom entry, etc).

## Build wiring

Release KAS configs list `pv-flash-bundle` as a build target alongside the
image. Toradex machines also list the recovery multiconfig target; Variscite
machines don't need one:

```yaml
# verdin-imx8mm-scarthgap.yaml / colibri-imx6ull-scarthgap.yaml
target:
- pantavisor-starter
- mc:tezi-recovery:u-boot-toradex
- pv-flash-bundle
```

```yaml
# imx8mm-var-dart-scarthgap.yaml / imx8mn-var-som-scarthgap.yaml /
# imx8qxp-b0-mek-scarthgap.yaml / rockchip-orangepi-5b-scarthgap.yaml
target:
- pantavisor-starter
- pv-flash-bundle
```

The `target:` list comes from the `build-base-*-starter.yaml` a machine's config
chain ends in (`.github/machines.json`): `build-base-toradex-starter.yaml` adds
`pv-flash-bundle` plus the recovery multiconfig, while
`build-base-pvflash-starter.yaml` just adds `pv-flash-bundle` (used by every
non-Toradex bundle machine — Variscite, NXP MEK, Rockchip). A machine's own
`kas/machines/<machine>.yaml` cannot contribute here: kas *replaces* `target`
with the value from the last file in the chain, and the machine yaml is first.

```bash
kas build kas/build-configs/release/verdin-imx8mm-scarthgap.yaml
```

Artifacts land at
`build/tmp-${codename}/deploy/images/${machine}/pv-flash-bundle-${machine}.tar.gz`.

## Adding a new machine

1. Add `recipes-bsp/pv-flash/files/<machine>/flash.sh.in` (and, for UUU
   machines, `uuu.auto.in`).
2. Set `PV_FLASH_FLASH_SCRIPT_IN:<machine>` (and `PV_FLASH_UUU_SCRIPT_IN:<machine>`
   for UUU) to `file://flash.sh.in` / `file://uuu.auto.in` in `pv-flash-bundle.bb`.
3. Pick the flashing tool and the loader source:
   - **NXP i.MX, needs a stripped recovery build** (like Toradex): keep
     `PV_FLASH_TOOL = "uuu"`; set `PV_FLASH_RECOVERY_MC` /
     `PV_FLASH_RECOVERY_RECIPE` / `PV_FLASH_RECOVERY_IMAGE` in the machine's
     `kas/machines/<machine>.yaml`, and add the recovery multiconfig target to
     the release build-config.
   - **NXP i.MX, production bootloader already self-enters SDP/fastboot** (like
     Variscite — check the SoC vendor SPL for `CONFIG_SPL_USB_SDP_SUPPORT`, or a
     vendor single-build uuu installer recipe): keep `PV_FLASH_TOOL = "uuu"`; set
     `PV_FLASH_BOOT_IMAGE:<machine>` (a glob) directly in `pv-flash-bundle.bb`.
   - **Rockchip** (like `orangepi-5b`): set `PV_FLASH_TOOL:<machine> = "rkdeveloptool"`
     and `PV_FLASH_RK_LOADER:<machine>` to the glob for a Maskrom-capable USB
     loader in the main build's `DEPLOY_DIR_IMAGE` (the JeffyCN BSP deploys
     `loader.bin`; a mainline-U-Boot BSP has none prebuilt and needs one merged
     from rkbin with `boot_merger` first).
4. For NAND machines, also set `PV_FLASH_NAND_UBOOT` / `PV_FLASH_UBIFS`.
5. End the machine's `.github/machines.json` config chain with
   `build-base-pvflash-starter.yaml` (or `build-base-toradex-starter.yaml` for
   the recovery-multiconfig case) — this is what puts `pv-flash-bundle` on the
   `target:` list; the machine yaml can't. Add `build_target: ""` +
   `output: "pv-flash-bundle-<machine>.tar.gz"`, then run
   `.github/scripts/makemachines` and `.github/scripts/makeworkflows`.

No changes to `pv-flash-bundle.bb`'s `do_deploy` logic are needed unless the
new machine requires a genuinely new flash topology beyond eMMC-wic,
eMMC-boot-image, NAND-UBIFS, or Rockchip Maskrom.

## Related

- [Flashing Toradex Modules](../getting-started/how-to-install/toradex.md) — end-user flashing
  procedure, prerequisites, and troubleshooting
- [Starter Image](images.md) — `pantavisor-starter`, the default `PV_FLASH_IMAGE`
- [Build System](build-system.md) — KAS multiconfig mechanics behind
  `PV_FLASH_RECOVERY_MC`
