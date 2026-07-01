---
sidebar_position: 7
---
# pv-flash-bundle Recipe

`pv-flash-bundle` (`recipes-bsp/pv-flash/pv-flash-bundle.bb`) assembles a
self-contained factory flash archive for boards that flash via NXP's UUU tool
instead of a standard `.wic` write. It bundles the image payload, a portable
`uuu` binary, a recovery U-Boot, and generated flash scripts into a single
`pv-flash-bundle-${MACHINE}.tar.gz`.

For the end-user flashing procedure, see
[Flashing Toradex Modules](../how-to-install/toradex.md) and
[Flashing via NXP uuu](../how-to-install/uuu.md) (Variscite). This page covers
how the recipe itself is built and how to wire up a new machine.

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
| `PV_FLASH_RECOVERY_MC` | Multiconfig that builds the recovery U-Boot | *(none)* |
| `PV_FLASH_RECOVERY_RECIPE` | Recipe to build in that multiconfig (e.g. `u-boot-toradex`) | *(none)* |
| `PV_FLASH_RECOVERY_IMAGE` | Filename of the recovery U-Boot in the recovery MC's deploy dir | *(none)* |
| `PV_FLASH_BOOT_IMAGE` | Glob for a boot binary sourced directly from the **main build's** `DEPLOY_DIR_IMAGE` — for machines whose production bootloader already self-enters SDP/fastboot download mode | *(none, set for `imx8mm-var-dart`/`imx8mn-var-som`/`imx8qxp-b0-mek`)* |
| `PV_FLASH_NAND_UBOOT` | Production NAND U-Boot filename (NAND machines only) | *(none, set for `colibri-imx6ull`)* |
| `PV_FLASH_UBIFS` | UBIFS rootfs filename (NAND machines only) | *(none, set for `colibri-imx6ull`)* |
| `PV_FLASH_UUU_SCRIPT_IN` | `file://uuu.auto.in` template SRC_URI entry | *(none)* |
| `PV_FLASH_FLASH_SCRIPT_IN` | `file://flash.sh.in` template SRC_URI entry | *(none)* |

Leaving `PV_FLASH_UBIFS`/`PV_FLASH_NAND_UBOOT` empty (the eMMC default) makes
`do_deploy` bundle the `.wic.gz` (+ `.wic.bmap` if present) instead of a raw
UBIFS image.

## `do_deploy` steps

1. **Rootfs artifact** — installs `${PV_FLASH_IMAGE}-${MACHINE}.rootfs.ubifs`
   if `PV_FLASH_UBIFS` is set, otherwise the `.wic.gz` (+ `.wic.bmap`).
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
5. **UUU binary** — copies `uuu` from `uuu-native:do_populate_sysroot` into
   the bundle, then runs `patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 --set-rpath ""`
   so the binary runs on an arbitrary x86-64 Linux host regardless of its
   build sysroot.
6. **Script generation** — `sed`-expands `@WIC@ @WIC_GZ@ @UBIFS@ @UBOOT_NAND@ @RECOVERY_IMAGE@`
   in `uuu.auto.in` and `flash.sh.in` (staged via `FILESEXTRAPATHS:prepend`
   from `files/${MACHINE}/`) into `uuu.auto` and `flash.sh` in the bundle.
   `imx-boot.bin` (from step 4) is referenced as a literal filename in those
   templates instead, since its bundle name is fixed by the recipe rather
   than expanded from a variable.
7. **Package** — tars the bundle directory as
   `${PN}-${MACHINE}.tar.gz` and symlinks `${PN}-${MACHINE}-latest.tar.gz`.

## Per-machine templates

Machine-specific UUU logic lives entirely in `files/<machine>/uuu.auto.in`
and `files/<machine>/flash.sh.in` — the recipe code is identical for every
machine.

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
  switch to make.
- **imx8qxp-b0-mek** (eMMC, NXP eval board): a single `SDPS: boot -scanterm`
  command instead of `SDP:`/`SDPV:` — i.MX8QXP/8QM silicon's ROM supports
  "stream" SDP mode, where the SCU loads the whole boot container (SCFW +
  ATF + OP-TEE + U-Boot) in one transfer with no separate SPL-jump step to
  script. Then the same `FB: flash -raw2sparse all @WIC@` as the other eMMC
  machines. `mmc dev 0` targets eMMC on this board: `usdhc1` (`mmc-hs400-1_8v`
  — an eMMC-only speed mode) probes before `usdhc2` (`sd-uhs-sdr104` — SD
  card), and no `/aliases` override reorders them, so `usdhc1` gets U-Boot
  device index 0.

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

See [Flashing Toradex Modules](../how-to-install/toradex.md#how-the-flash-sequence-works)
and [Flashing via NXP uuu](../how-to-install/uuu.md) for the full step-by-step
sequences and hardware-specific notes (NAND geometry, udev rules, boot-mode
switches, etc).

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
# imx8mm-var-dart-scarthgap.yaml / imx8mn-var-som-scarthgap.yaml / imx8qxp-b0-mek-scarthgap.yaml
target:
- pantavisor-starter
- pv-flash-bundle
```

```bash
kas build kas/build-configs/release/verdin-imx8mm-scarthgap.yaml
```

Artifacts land at
`build/tmp-${codename}/deploy/images/${machine}/pv-flash-bundle-${machine}.tar.gz`.

## Adding a new UUU-flashable machine

1. Add `recipes-bsp/pv-flash/files/<machine>/uuu.auto.in` and `flash.sh.in`.
2. Set `PV_FLASH_UUU_SCRIPT_IN:<machine>` / `PV_FLASH_FLASH_SCRIPT_IN:<machine>`
   to `file://uuu.auto.in` / `file://flash.sh.in` in `pv-flash-bundle.bb`.
3. Pick a boot-image source, depending on whether the production bootloader
   already self-enters SDP/fastboot download mode (check the SoC vendor's
   SPL source for a `CONFIG_SPL_USB_SDP_SUPPORT`-style ROM-level handoff, or
   look for a vendor-shipped single-build uuu installer recipe as evidence):
   - **Needs a stripped recovery build** (like Toradex): set
     `PV_FLASH_RECOVERY_MC` / `PV_FLASH_RECOVERY_RECIPE` / `PV_FLASH_RECOVERY_IMAGE`
     in the machine's `kas/machines/<machine>.yaml`, and add the recovery
     multiconfig target to the release build-config.
   - **Production bootloader already works** (like Variscite): set
     `PV_FLASH_BOOT_IMAGE:<machine>` (a glob) directly in `pv-flash-bundle.bb`
     — no new multiconfig, no machine-yaml changes needed for this variable.
4. For NAND machines, also set `PV_FLASH_NAND_UBOOT` / `PV_FLASH_UBIFS`.
5. Add `pv-flash-bundle` (and the recovery multiconfig target, if used) to
   the machine's release build-config `target` list.

No changes to `pv-flash-bundle.bb`'s `do_deploy` logic are needed unless the
new machine requires a genuinely new flash topology beyond eMMC-wic,
eMMC-boot-image, or NAND-UBIFS.

## Related

- [Flashing Toradex Modules](../how-to-install/toradex.md) — end-user flashing
  procedure, prerequisites, and troubleshooting
- [Starter Image](images.md) — `pantavisor-starter`, the default `PV_FLASH_IMAGE`
- [Build System](build-system.md) — KAS multiconfig mechanics behind
  `PV_FLASH_RECOVERY_MC`
