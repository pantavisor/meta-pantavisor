---
sidebar_position: 3
---
# Build System

[meta-pantavisor](https://github.com/pantavisor/meta-pantavisor) is the
Yocto/OpenEmbedded layer that builds Pantavisor-based BSP images for embedded
Linux products. It provides recipes, BitBake classes, and KAS configurations
for producing initramfs images and container pvrexport bundles. For the build
workflow itself, see [Get started](get-started.md).

## Key Directories

```
meta-pantavisor/
├── classes/                    # BitBake classes
├── conf/                       # Layer and distro configuration
│   └── multiconfig/            # Per-multiconfig TMPDIR settings
├── dynamic-layers/             # Conditional recipes for other layers
├── kas/                        # KAS configuration fragments
│   ├── build-configs/          # One-file release build configs
│   ├── machines/               # Per-machine configurations
│   └── platforms/              # Platform-specific layer includes
├── recipes-containers/
│   └── pv-examples/            # Example containers for xconnect testing
├── recipes-pv/                 # Core pantavisor recipes
│   ├── images/                 # Appengine and BSP image recipes
│   ├── pantavisor/             # Pantavisor runtime
│   └── pvr/                    # PVR tool
├── recipes-devtools/           # Development tools (json-sh, fdisk)
└── wic/                        # WIC disk image layout files
```

## Key Recipes

| Recipe | Description |
|--------|-------------|
| `recipes-pv/pantavisor/pantavisor_git.bb` | Core Pantavisor runtime (C, cmake-based); `SRCREV` forwarded from `pantavisor.inc` |
| `recipes-pv/images/pantavisor-initramfs.bb` | Initramfs image |
| `recipes-pv/images/pantavisor-bsp.bb` | BSP image (generates pvrexport bundles) |
| `recipes-pv/images/pantavisor-starter.bb` | Flashable starter disk image (`.wic`) |
| `recipes-pv/pvr/pvr_*.bb` | PVR CLI tool (Go-based) |
| `recipes-pv/lxc-pv/lxc-pv_git.bb` | Pantavisor-specific LXC fork |

## BitBake Classes

| Class | Description |
|-------|-------------|
| `classes/pvbase.bbclass` | Defines `PANTAVISOR_FEATURES` variable and defaults |
| `classes/pvrexport.bbclass` | PVR export functionality for images |
| `classes/container-pvrexport.bbclass` | Container pvrexport packaging |
| `classes/pvr-ca.bbclass` | Certificate authority handling |
| `classes/pvroot-image.bbclass` | Root container image support |

## KAS Configuration Hierarchy

KAS is the primary build system. Configuration is composed by layering YAML fragments:

| File | Description |
|------|-------------|
| `kas/bsp-base.yaml` | Base configuration for BSP builds; defines repos and core settings |
| `kas/bsp-multi.yaml` | Multiconfig builds (separate configs for initramfs and containers) |
| `kas/scarthgap.yaml` / `kas/kirkstone.yaml` | Yocto release-specific patches and branches |
| `kas/machines/*.yaml` | Per-machine configurations |
| `kas/platforms/*.yaml` | Platform-specific layer includes (sunxi, raspberrypi, etc.) |
| `kas/with-workspace.yaml` | Overlay for local pantavisor source development |

## Multiconfig Architecture

When using `bsp-multi.yaml`, builds use three separate multiconfigs to avoid TMPDIR conflicts:

| Multiconfig | Purpose | Config file |
|-------------|---------|-------------|
| `default` | Main image build | — |
| `pv-initramfs-panta` | Initramfs with musl libc | `conf/multiconfig/pv-initramfs-panta.conf` |
| `pv-panta` | Container builds | `conf/multiconfig/pv-panta.conf` |

Each multiconfig uses a separate TMPDIR, set in its conf file:
```
# conf/multiconfig/pv-initramfs-panta.conf
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-pv-initramfs-panta"

# conf/multiconfig/pv-panta.conf
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-pv-panta"
```

(Only the Raspberry Pi kernel-variant multiconfigs append `${MACHINE}` — see below.)

## PANTAVISOR_FEATURES

Controls which optional Pantavisor components are compiled in and installed. Defined in `classes/pvbase.bbclass`. The table below lists the commonly used features, not an exhaustive set:

| Feature | Description |
|---------|-------------|
| `dm-crypt` | Storage encryption |
| `dm-verity` | Container rootfs integrity verification |
| `autogrow` | Automatic partition growing |
| `runc` | OCI runtime support |
| `tailscale` | Tailscale VPN integration |
| `debug` | Debug features |
| `pvcontrol` | pv-ctrl socket and CLI tools (pvcurl, pvcontrol) |
| `xconnect` | Service mesh for container-to-container communication |
| `container-mdev` | Per-container mdev device-node hook (runs an mdev LXC mount hook on each container start) |
| `rngdaemon` | Random number generator daemon |
| `squash-lz4` | LZ4 squashfs compression |
| `squash-zstd` | Zstd squashfs compression |
| `rpi-tryboot` | Raspberry Pi A/B boot partition support |
| `bootchartd` | Boot timing analysis (writes to `/`; use `rdinit=/sbin/bootchartd`) |

**Default**: `dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect container-mdev`

> **Caution**: `tailscale` and `rngdaemon` appear in the default string, but their gating is inconsistent upstream — for example, `pantavisor-initramfs.bb` checks for a feature named `rngd`, not `rngdaemon`. Verify the recipes if you depend on either.

### The `+=` vs `:append` Pitfall

`pvbase.bbclass` sets defaults via `??=` (weak default operator):

```bitbake
PANTAVISOR_FEATURES ??= " dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect container-mdev "
```

In distro includes, you **must** use `:append` or `:remove` — never `+=`:

```bitbake
# WRONG — clobbers ??= defaults, silently drops xconnect, pvcontrol, rngdaemon
PANTAVISOR_FEATURES += "appengine"

# CORRECT — preserves ??= defaults and appends
PANTAVISOR_FEATURES:append = " appengine"
```

## Raspberry Pi Tryboot (rpi-tryboot)

The `rpi-tryboot` feature enables A/B boot partition support for Raspberry Pi, building a unified boot image supporting all RPi variants from a single build.

**Configuration:** `kas/machines/rpi.yaml`

### Kernel Variant Multiconfigs

| Multiconfig | Machine | Target |
|-------------|---------|--------|
| `rpi-kernel.conf` | raspberrypi | Pi 0/1 |
| `rpi-kernel7.conf` | raspberrypi2 | Pi 2/3 32-bit |
| `rpi-kernel7l.conf` | raspberrypi-armv7 | Pi 4 32-bit |
| `rpi-kernel8.conf` | raspberrypi-armv8 | Pi 3/4 64-bit |
| `rpi-kernel_2712.conf` | raspberrypi5 | Pi 5 |

Each uses a separate TMPDIR: `tmp-${DISTRO_CODENAME}-rpi-kernel-${MACHINE}`.

### Key Recipes

- `dynamic-layers/meta-raspberrypi/recipes-pv/images/rpi-boot-image.bb` — FAT32 boot partition with all kernel variants
- `dynamic-layers/meta-raspberrypi/recipes-pv/images/rpi-bootsel.bb` — Boot selector partition with `autoboot.txt`
- WKS file: `wic/rpi-tryboot-ab.wks`

### Partition Layout

```
Partition 1 (bootsel):  FAT16 — autoboot.txt, bootcode.bin (A/B selector)
Partition 2 (boot_a):   FAT32 — kernels, DTBs, config.txt, initramfs
Partition 3 (boot_b):   FAT32 — same as boot_a (for A/B switching)
Partition 4 (root):     ext4  — rootfs with /trails/0 pvr state
```

### Output Artifacts

These are packed into the `bsp/` directory of the BSP pvrexport state (by
`pantavisor-bsp.bb`), not shipped as standalone deploy files:

- `pantavisor-rpi.img.gz` — Gzipped boot partition
- `modules_<version>.squashfs` — Per-kernel-version modules (e.g. `modules_6.6.63-v8+.squashfs`)
- `firmware.squashfs` — Shared firmware

## Output Artifacts

Build outputs are in `build/tmp-{codename}/deploy/images/{machine}/`:

| Artifact | Description |
|----------|-------------|
| `*.pvrexport.tgz` | Pantavisor export bundles (main deployment artifact) |
| `*.wic` / `*.wic.bz2` | Complete disk images |
| `pantavisor-initramfs-*.cpio.gz` | Initramfs image |
| `pantavisor-appengine-docker.tar` | Docker image for manual appengine testing |
| `pantavisor-appengine-distro-docker-x86_64-*.tar.gz` | Self-contained test bundle: Docker images + `test.docker.sh` runner |

## Supported Yocto Releases

| Release | Status |
|---------|--------|
| scarthgap | Primary (CI-tested) |
| kirkstone | Supported (LTS) |

Both scarthgap and kirkstone are Yocto LTS releases.

Layer compatibility is declared in `conf/layer.conf`:
```
LAYERSERIES_COMPAT_meta-pantavisor = "kirkstone scarthgap"
```

## Key Build Paths

| Path | Description |
|------|-------------|
| `build/workspace/sources/pantavisor/` | Pantavisor source (workspace builds) |
| `build/tmp-scarthgap/deploy/images/` | Build outputs |
| `recipes-containers/pv-examples/` | Example container recipes |
| `kas/build-configs/release/` | KAS release machine configurations |
| `.github/configs/release/` | CI release machine configurations |
