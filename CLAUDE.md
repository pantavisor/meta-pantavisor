# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

meta-pantavisor is a Yocto/OpenEmbedded layer for building Pantavisor, a container-based embedded Linux system runtime. It provides recipes, classes, and configurations for building complete BSP images with container support.

## Build Commands

### Using KAS (Recommended)

KAS is the primary build system. Configuration is managed through YAML files and a Kconfig-based menu system.

```bash
# Interactive configuration menu
kas menu Kconfig

# Build with a specific configuration (generated .config.yaml)
kas build .config.yaml

# Build specific target combinations
kas build kas/scarthgap.yaml:kas/machines/raspberrypi-armv8.yaml:kas/bsp-base.yaml
```

### Common Build Targets

- `pantavisor-bsp` - Full BSP image with Pantavisor initramfs
- `pantavisor-initramfs` - Standalone initramfs with Pantavisor runtime
- `pantavisor-remix` - BSP with root container support
- `pantavisor-starter` - Minimal starter image
- `pantavisor-appengine` - Docker-based appengine builds

### Direct BitBake (if environment is set up)

```bash
source layers/poky/oe-init-build-env build
bitbake pantavisor-bsp
```

## Architecture

### KAS Configuration Hierarchy

- `kas/bsp-base.yaml` - Base configuration for BSP builds, defines repos and core settings
- `kas/bsp-multi.yaml` - Multiconfig builds (separate configs for initramfs and containers)
- `kas/scarthgap.yaml` / `kas/kirkstone.yaml` - Yocto release-specific patches and branches
- `kas/machines/*.yaml` - Per-machine configurations
- `kas/platforms/*.yaml` - Platform-specific layer includes (sunxi, raspberrypi, etc.)

### Key Recipes

- `recipes-pv/pantavisor/pantavisor_git.bb` - Core Pantavisor runtime (C, cmake-based)
- `recipes-pv/images/pantavisor-initramfs.bb` - Initramfs image recipe
- `recipes-pv/images/pantavisor-bsp.bb` - BSP image recipe (generates pvrexport bundles)
- `recipes-pv/pvr/pvr_*.bb` - PVR CLI tool (Go-based)
- `recipes-pv/lxc-pv/lxc-pv_git.bb` - Pantavisor-specific LXC fork

### BitBake Classes

- `classes/pvbase.bbclass` - Defines `PANTAVISOR_FEATURES` variable
- `classes/pvrexport.bbclass` - PVR export functionality for images
- `classes/pvr-ca.bbclass` - Certificate authority handling
- `classes/pvroot-image.bbclass` - Root container image support

### PANTAVISOR_FEATURES

Controls optional Pantavisor components (defined in `pvbase.bbclass`):
- `dm-crypt`, `dm-verity` - Disk encryption/verification
- `autogrow` - Automatic partition growing
- `runc` - OCI runtime support
- `tailscale` - Tailscale VPN integration
- `debug` - Debug features
- `pvcontrol` - PV control socket support
- `squash-lz4`, `squash-zstd` - Compression options
- `rpi-tryboot` - Raspberry Pi A/B boot partition support (see below)

### Multiconfig Architecture

When using `bsp-multi.yaml`, builds use three multiconfigs:
- `default` - Main image build
- `pv-initramfs-panta` - Initramfs with musl libc (`conf/multiconfig/pv-initramfs-panta.conf`)
- `pv-panta` - Container builds (`conf/multiconfig/pv-panta.conf`)

### Raspberry Pi Tryboot (rpi-tryboot)

The `rpi-tryboot` feature enables A/B boot partition support for Raspberry Pi, building a unified boot image supporting all RPi variants.

**Configuration:** `kas/machines/rpi.yaml`

**Multiconfigs for kernel variants** (in `conf/multiconfig/`):
- `rpi-kernel.conf` - Pi 0/1 (MACHINE=raspberrypi)
- `rpi-kernel7.conf` - Pi 2/3 32-bit (MACHINE=raspberrypi2)
- `rpi-kernel7l.conf` - Pi 4 32-bit (MACHINE=raspberrypi-armv7)
- `rpi-kernel8.conf` - Pi 3/4 64-bit (MACHINE=raspberrypi-armv8)
- `rpi-kernel_2712.conf` - Pi 5 (MACHINE=raspberrypi5)

Each multiconfig uses a separate TMPDIR (`tmp-${DISTRO_CODENAME}-rpi-kernel-${MACHINE}`) to avoid build conflicts.

**Key recipes:**
- `recipes-pv/images/rpi-boot-image.bb` - FAT32 boot partition with all kernel variants
- `recipes-pv/images/rpi-bootsel.bb` - Boot selector partition with autoboot.txt
- WKS file: `wic/rpi-tryboot-ab.wks`

**BSP output artifacts:**
- `pantavisor-rpi.img.gz` - Gzipped boot partition
- `modules_<version>.squashfs` - Per-kernel-version modules (e.g., `modules_6.1.77-v8+.squashfs`)
- `firmware.squashfs` - Shared firmware

**Current partition layout** (wic/rpi-tryboot-ab.wks):
```
Partition 1 (bootsel):  FAT32 - autoboot.txt, bootcode.bin (A/B selector)
Partition 2 (boot_a):   FAT32 - kernels, DTBs, config.txt, initramfs (rawcopy of rpi-boot-image.vfat)
Partition 3 (boot_b):   FAT32 - same as boot_a (for A/B switching)
Partition 4 (root):     ext4  - rootfs with /trails/0 pvr state
```

**Future: Signed boot.img support**

The RPi bootloader supports booting from a `boot.img` file placed inside a FAT partition. This enables boot image signing:

```
Partition 2 (boot_a):   FAT32 containing boot.img (+ boot.img.sig)
Partition 3 (boot_b):   FAT32 containing boot.img (+ boot.img.sig)
```

Where `boot.img` is the FAT image (current rpi-boot-image.vfat) with kernels, config.txt, initramfs, etc. Implementation would require:
1. Create wrapper FAT partition recipe containing boot.img
2. Update WKS to use wrapper partitions instead of rawcopy
3. Add signature generation and verification support

### Supported Yocto Releases

- kirkstone (LTS)
- scarthgap (current)

Layer compatibility defined in `conf/layer.conf`: `LAYERSERIES_COMPAT_meta-pantavisor = "kirkstone scarthgap"`

## Output Artifacts

Build outputs are in `build/tmp-{codename}/deploy/images/{machine}/`:
- `*.pvrexport.tgz` - Pantavisor export bundles (main deployment artifact)
- `*.wic` / `*.wic.bz2` - Complete disk images
- `pantavisor-initramfs-*.cpio.gz` - Initramfs image

## CI/CD

GitHub Actions workflows in `.github/workflows/`:
- `buildkas-target.yaml` - Reusable workflow for building targets
- `buildkas-upload.yaml` - Upload artifacts to S3
- `manual-*.yaml` - Manual build triggers per machine
- `tag-*.yaml` - Tag-triggered builds per machine
- `onpush-*.yaml` - Push-triggered builds (subset of machines)

### Machine Configuration and Workflows

**IMPORTANT:** When adding or modifying machines, always follow this process:

1. **Edit `.github/machines.json`** - Define the machine configuration:
   ```json
   {
       "config": "kas/machines/MACHINE.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:.github/configs/build-base-starter.yaml",
       "name": "MACHINE-NAME",
       "workflows": ["manual", "tag"]  // or ["manual", "tag", "onpush"]
   }
   ```

2. **Regenerate workflows** - Run the makeworkflows script:
   ```bash
   .github/scripts/makeworkflows
   ```
   This generates/updates workflow files in `.github/workflows/` based on machines.json.

3. **Commit both** - Always commit machines.json AND the generated workflow files together.

**Workflow types:**
- `manual` - Manually triggered via GitHub Actions UI
- `tag` - Triggered on git tags (for releases)
- `onpush` - Triggered on every push (use sparingly, only for key machines)

**Optional machine properties:**
- `sdk`: 1 - Build SDK for this machine
- `output`: "pattern" - Custom output file pattern
- `build_target`: "recipe" - Override default build target

## Common Issues

### Pseudo Path Mismatch Errors

If you see errors like `path mismatch [1 link]: ino XXXXX db '...' req '...'` during image builds, this is a pseudo database corruption issue. The pvr tool's file operations can confuse pseudo's inode tracking.

**Fix with KAS:**
```bash
kas shell <config.yaml> -c "bitbake -c cleansstate <recipe-name>"
kas build <config.yaml>
```

**Fix with BitBake (for integrators):**
```bash
bitbake -c cleansstate <recipe-name>
bitbake <recipe-name>
```

The `pvroot-image.bbclass` includes `PSEUDO_IGNORE_PATHS` entries to mitigate this for pvr working directories.

### Multiconfig TMPDIR Conflicts

When using BBMULTICONFIG, each config should have a separate TMPDIR to avoid conflicts with package feeds, sstate, and deploy directories. Example pattern:
```
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-${MULTICONFIG_NAME}-${MACHINE}"
```

## KAS vs BitBake Commands

This layer is designed to be used with KAS. Below are common commands in both formats:

| Task | KAS (Recommended) | BitBake (for integrators) |
|------|-------------------|---------------------------|
| Build image | `kas build <config.yaml>` | `bitbake pantavisor-bsp` |
| Clean recipe | `kas shell <config.yaml> -c "bitbake -c clean <recipe>"` | `bitbake -c clean <recipe>` |
| Clean sstate | `kas shell <config.yaml> -c "bitbake -c cleansstate <recipe>"` | `bitbake -c cleansstate <recipe>` |
| Rebuild recipe | `kas shell <config.yaml> -c "bitbake -c compile -f <recipe>"` | `bitbake -c compile -f <recipe>` |
| devshell | `kas shell <config.yaml> -c "bitbake -c devshell <recipe>"` | `bitbake -c devshell <recipe>` |
| Interactive shell | `kas shell <config.yaml>` | `source oe-init-build-env` |

**Note:** Integrators who include meta-pantavisor in their own Yocto builds may use BitBake directly without KAS.
