---
sidebar_position: 5
---
# U-Boot Boot Flow

How Pantavisor boots from U-Boot via the generic boot script
`boot.cmd.pvgeneric`. This is the U-Boot → kernel handoff that runs before
the Pantavisor runtime takes over as init.

## The Pantavisor boot model

Pantavisor does not boot a normal root filesystem. Instead the kernel is
started with a ramfs root and Pantavisor as the init process:

```
root=/dev/ram rootfstype=ramfs rdinit=/usr/bin/pantavisor
```

The kernel + initramfs + device tree are packaged as a FIT image
(`pantavisor.fit`) that lives inside a versioned **trail revision** on the
storage volume:

```
/trails/<rev>/bsp/pantavisor.fit          # preferred: single FIT
/trails/<rev>/.pv/pv-kernel.img           # fallback: separate components
/trails/<rev>/.pv/pv-initrd.img
/trails/<rev>/.pv/pv-fdt.dtb
```

U-Boot's only job is to pick the right revision, load that revision's
kernel/initrd/dtb into RAM, assemble the kernel command line, and jump to
it. Once running, Pantavisor mounts its storage volume and manages
containers (see [Pantavisor](pantavisor.md) for the trail/revision model).

## How the boot script is built and deployed

The script source is `recipes-bsp/u-boot/files/boot.cmd.pvgeneric`. It is
wired into every U-Boot build by `recipes-bsp/u-boot/u-boot%.bbappend`:

| Step | Mechanism |
|------|-----------|
| Assemble source | `do_prepcompile` concatenates `UBOOT_ENV_SRC_FRAGS` (i.e. `boot.cmd.pvgeneric`) into `boot.txt` / `boot.cmd` |
| Compile | The U-Boot recipe wraps it with `mkimage` into `boot.scr` (`UBOOT_ENV=boot`, `UBOOT_ENV_SUFFIX=scr`) |
| Deploy | `boot.scr` lands in `DEPLOY_DIR_IMAGE`; image recipes place it where U-Boot expects it |
| OEM args | `do_deploy:append` renders `oemEnv.txt` from its template, substituting `@@PV_BOOT_OEMARGS@@` → `PV_BOOT_OEMARGS` |

The `pvbsp` / `pvapp` multiconfigs disable the env (`UBOOT_ENV = ""`) since
they do not produce a bootable top-level image.

## Where boot.scr lives per storage backend

`boot.scr` is loaded and `source`d by U-Boot's `bootcmd`. How that happens
depends on the storage medium:

| Backend | How bootcmd finds boot.scr | boot.scr placement |
|---------|----------------------------|--------------------|
| MMC / wic (eMMC, SD) | `distro_bootcmd` scans the FAT boot partition for `boot.scr` | `IMAGE_BOOT_FILES` puts it on the FAT partition |
| NAND / UBIFS | A machine `bootcmd` mounts the UBI volume and sources it directly | `pantavisor-starter.bb` copies it into the rootfs `/boot/` |

For NAND the default `bootcmd` (set via a machine U-Boot `.cfg` such as
`pv.colibri-imx6ull.cfg`) is:

```
ubi part ubi && ubifsmount ubi0:boot && setenv devtype ubi && \
    ubifsload ${scriptaddr} /boot/boot.scr && source ${scriptaddr}
```

Note `setenv devtype ubi` — the boot script keys all of its load behavior
off `${devtype}` (see below).

## The boot script, step by step

1. **Base args.** Sets `pv_baseargs` (`root=/dev/ram … rdinit=/usr/bin/pantavisor`)
   and appends `console=${console},${baudrate}` when known.

2. **Pick a load method.** `${devtype}` selects how files are read:
   - `devtype != ubi` (mmc, usb, …) → `${pv_load_boot}` / `${pv_load_data}`
     expand to `load <devtype> <dev>:<part>` (fatload/ext4load).
   - `devtype = ubi` → both collapse to `ubifsload` (a single UBIFS volume
     holds everything). U-Boot's generic `load` cannot read UBIFS, so this
     indirection is required. `pv_root` adds the leading `/` that absolute
     UBIFS paths need for files at the volume root.

3. **Load `oemEnv.txt`** and `env import` it → provides `${oemargs}`
   (see [OEM args](#oem-args-and-pv_boot_oemargs)).

4. **Locate the data partition / OEM config (MMC only).** On MMC the script
   probes partition `${pv_ctrl}` (2) for a small Pantavisor OEM config
   (size `0x800`) and computes `pv_mmcdata` (the rootfs/data partition).
   On UBI this MBR probe is skipped — there is one volume.

5. **Load revision state.**
   - `/boot/uboot.txt` → `pv_rev` (the committed revision).
   - `pv.env` → `pv_try` / `pv_trying` (try-boot markers).

6. **Select `boot_rev` (try-boot / rollback).**
   - No `pv_try` → boot the committed `pv_rev`.
   - `pv_try` set and not yet attempted → boot `pv_try` and record it in
     `pv.env` (first attempt of a new revision).
   - `pv_try` set and already attempted (previous try failed) → fall back
     to the committed `pv_rev`.
   - The recorded state is written back with `save … pv.env`. **On UBI this
     `save` is skipped** — U-Boot's UBIFS driver is read-only, so try-boot
     rollback state is not persisted on NAND.

7. **Boot the FIT.** Tries `/trails/${boot_rev}/bsp/pantavisor.fit`. If
   present, selects a config node (`name_fit_config`) and `bootm`s it. The
   config node is resolved via, in order: a platform hook
   (`pv_plat_set_name_fit_config`), the board's `findfdt`, or `fdtfile`.

8. **Fallback to discrete images.** If no FIT, loads `pv-kernel.img`,
   `pv-initrd.img`, `pv-fdt.dtb` (plus any `pv-initrd.img.<n>` add-ons) from
   `/trails/${boot_rev}/.pv/`, then tries `booti` → `bootz` → `bootm` →
   `bootelf` in turn.

9. **Final command line.** Assembled as:
   ```
   ${pv_platargs} ${pv_baseargs} pv_try=… pv_rev=… panic=2 pv_quickboot \
       ${fdtbootargs} ${configargs} ${oemargs} ${localargs}
   ```

## OEM args and PV_BOOT_OEMARGS

`PV_BOOT_OEMARGS` (set per machine) is the supported hook for injecting
extra kernel command-line arguments. It flows:

```
PV_BOOT_OEMARGS  →  oemEnv.txt (@@PV_BOOT_OEMARGS@@)  →  env import  →  ${oemargs}  →  bootargs
```

Pantavisor reads `pv_`-prefixed cmdline keys as config overrides (e.g.
`pv_storage.device`, `pv_storage.fstype`). Example for NAND/UBIFS:

```bitbake
PV_BOOT_OEMARGS = "mtdparts=gpmi-nand:512k(mx6ull-bcb),1536k(u-boot1)ro,1536k(u-boot2)ro,512k(u-boot-env),-(ubi) ubi.mtd=ubi pv_storage.device=ubi0:boot pv_storage.fstype=ubifs"
```

Here `ubi.mtd=ubi` tells the kernel to attach the UBI device named `ubi`, and
the `pv_storage.*` keys tell Pantavisor which volume to mount as storage. On
NAND boards whose device tree declares no MTD partitions, the kernel only
learns the partition layout (and thus the `ubi` partition) from a `mtdparts=`
on the cmdline — without it `ubi.mtd=ubi` has nothing to attach. (On boards
that define partitions in the DT, the `mtdparts=` is unnecessary.)

## Customization knobs

| Knob | Where | Purpose |
|------|-------|---------|
| `PV_BOOT_OEMARGS` | machine yaml / release build-config | Extra kernel cmdline args via `oemEnv.txt` |
| `PV_MACHINE_UBOOT_CONFIGS` | machine yaml / release build-config | Per-machine U-Boot `.cfg` fragments (e.g. a NAND `bootcmd`, extra commands) |
| `pv_platargs` | U-Boot env | Platform-specific early args (default `earlyprintk`) |
| `pv_plat_set_name_fit_config` | U-Boot env | Platform hook to choose the FIT config node |
| `localargs` | U-Boot env | Site/local cmdline additions |

> When changing a machine's `local_conf_header` (including `PV_BOOT_OEMARGS`
> and `PV_MACHINE_UBOOT_CONFIGS`), mirror the change in **both**
> `kas/machines/<machine>.yaml` and the release build-config under
> `kas/build-configs/release/`, which inlines its own platform block.

## See also

- [docs/how-to-install/boards/colibri-imx6ull.md](../how-to-install/boards/colibri-imx6ull.md) — a worked NAND/UBIFS boot example
- [Build System](build-system.md) — multiconfig architecture (the flashed NAND U-Boot is built in the `tezi-recovery` multiconfig)
