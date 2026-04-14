# Build System Overview

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

Each multiconfig should use a separate TMPDIR:
```
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-${MULTICONFIG_NAME}-${MACHINE}"
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

- `recipes-pv/images/rpi-boot-image.bb` — FAT32 boot partition with all kernel variants
- `recipes-pv/images/rpi-bootsel.bb` — Boot selector partition with `autoboot.txt`
- WKS file: `wic/rpi-tryboot-ab.wks`

### Partition Layout

```
Partition 1 (bootsel):  FAT32 — autoboot.txt, bootcode.bin (A/B selector)
Partition 2 (boot_a):   FAT32 — kernels, DTBs, config.txt, initramfs
Partition 3 (boot_b):   FAT32 — same as boot_a (for A/B switching)
Partition 4 (root):     ext4  — rootfs with /trails/0 pvr state
```

### Output Artifacts

- `pantavisor-rpi.img.gz` — Gzipped boot partition
- `modules_<version>.squashfs` — Per-kernel-version modules (e.g. `modules_6.1.77-v8+.squashfs`)
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

## Key Build Paths

| Path | Description |
|------|-------------|
| `build/workspace/sources/pantavisor/` | Pantavisor source (workspace builds) |
| `build/tmp-scarthgap/deploy/images/` | Build outputs |
| `recipes-containers/pv-examples/` | Example container recipes |
| `.github/configs/release/` | KAS release machine configurations |
