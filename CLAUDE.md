# meta-pantavisor

Yocto/OpenEmbedded layer for building Pantavisor, a container-based embedded Linux system runtime. It provides recipes, classes, and configurations for building complete BSP images with container support.

## Documentation

| Document | Description |
|----------|-------------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Development workflow - building, testing, iterating on pantavisor and containers |
| [EXAMPLES.md](EXAMPLES.md) | Example containers for pv-xconnect service mesh (Unix, REST, D-Bus, DRM, Wayland) |
| [TESTPLANS.md](TESTPLANS.md) | Executable test plans for appengine validation (IPAM, xconnect, DRM) |
| [GEMINI.md](GEMINI.md) | Implementation notes, upstream changes, and known pitfalls |

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

# Build with release configs
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

# Development build (with local pantavisor workspace)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# Build specific target
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml --target <recipe>
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

### Testing with Appengine

```bash
# Load docker image
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar

# Run appengine (interactive mode)
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

# Start pantavisor
docker exec pva-test sh -c 'pv-appengine &'

# Check status
docker exec pva-test lxc-ls -f
```

**Important**: When testing new containers or changes to pvtx.d:
- Delete the storage volume to retrigger pvtx.d processing: `docker volume rm storage-test`
- Alternatively, remove the `.pvtx-done` marker: `docker exec pva-test rm /var/pantavisor/storage/.pvtx-done`
- The pvtx.d scripts only run once per storage volume (when `.pvtx-done` doesn't exist)

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
- `classes/container-pvrexport.bbclass` - Container pvrexport packaging
- `classes/pvr-ca.bbclass` - Certificate authority handling
- `classes/pvroot-image.bbclass` - Root container image support

### Directory Structure

```
meta-pantavisor/
├── classes/                    # BitBake classes (container-pvrexport, image-pvrexport)
├── conf/                       # Layer and distro configuration
├── dynamic-layers/             # Conditional recipes for other layers
├── kas/                        # KAS configuration fragments
├── recipes-containers/         # Container recipes
│   └── pv-examples/           # Example containers for testing
├── recipes-pv/                 # Core pantavisor recipes
│   ├── images/                # Appengine and BSP images
│   ├── pantavisor/            # Pantavisor runtime
│   └── pvr/                   # PVR tool
└── recipes-devtools/           # Development tools (json-sh, fdisk)
```

### Key Paths

| Path | Description |
|------|-------------|
| `build/workspace/sources/pantavisor/` | Pantavisor source (when using with-workspace.yaml) |
| `build/tmp-scarthgap/deploy/images/` | Build outputs (images, pvrexports) |
| `recipes-containers/pv-examples/` | Example container recipes |
| `recipes-pv/` | Core pantavisor recipes |
| `.github/configs/release/` | KAS machine configurations |

## PANTAVISOR_FEATURES

Controls optional Pantavisor components (defined in `pvbase.bbclass`):
- `dm-crypt`, `dm-verity` - Disk encryption/verification
- `autogrow` - Automatic partition growing
- `runc` - OCI runtime support
- `tailscale` - Tailscale VPN integration
- `debug` - Debug features
- `pvcontrol` - PV control socket and CLI tools
- `xconnect` - Service mesh for container-to-container communication
- `rngdaemon` - Random number generator daemon
- `squash-lz4`, `squash-zstd` - Compression options
- `rpi-tryboot` - Raspberry Pi A/B boot partition support (see below)

**Important**: Never use `PANTAVISOR_FEATURES +=` in distro includes — it clobbers the `??=` defaults from `pvbase.bbclass`. Always use `:append` or `:remove` operators.

Default features: `dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect`

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

## pv-xconnect Service Mesh

pv-xconnect mediates container-to-container communication:

- **Unix sockets**: Raw socket proxy with namespace injection
- **REST**: HTTP-over-UDS with identity headers (X-PV-Client, X-PV-Role)
- **D-Bus**: Policy-aware proxy with interface filtering
- **DRM**: Device node injection for graphics (card0, renderD128)
- **Wayland**: Compositor access for isolated UI rendering

Configuration:
- **Provider**: `services.json` declares exported services (uses `#spec: service-manifest-xconnect@1` format)
- **Consumer**: `args.json` with `PV_SERVICES_REQUIRED`/`PV_SERVICES_OPTIONAL`

Example services.json:
```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    {"name": "my-service", "type": "unix", "socket": "/run/my.sock"}
  ]
}
```

See `build/workspace/sources/pantavisor/xconnect/XCONNECT.md` for protocol specification.

### Example Containers

The `pv-examples` containers demonstrate pv-xconnect service mesh patterns:

| Container | Type | Role | Description |
|-----------|------|------|-------------|
| `pv-example-unix-server` | unix | provider | Raw Unix socket server |
| `pv-example-unix-client` | unix | consumer | Raw Unix socket client |
| `pv-example-rest-server` | rest | provider | HTTP-over-UDS server |
| `pv-example-rest-client` | rest | consumer | HTTP-over-UDS client |
| `pv-example-dbus-server` | dbus | provider | D-Bus service |
| `pv-example-dbus-client` | dbus | consumer | D-Bus client |
| `pv-example-drm-provider` | drm | provider | DRM device exporter |
| `pv-example-drm-master` | drm | consumer | DRM master (KMS) |
| `pv-example-drm-render` | drm | consumer | DRM render node |
| `pv-example-wayland-server` | wayland | provider | Weston compositor |
| `pv-example-wayland-client` | wayland | consumer | Wayland client |

See [EXAMPLES.md](EXAMPLES.md) for detailed testing instructions.

## Pantavisor Source Development

When using `kas/with-workspace.yaml`, workspace sources are available at:
```
build/workspace/sources/pantavisor/   # Pantavisor runtime
build/workspace/sources/lxc-pv/       # LXC with pantavisor patches (if added)
```

Workspace bbappend files redirect recipes to use local sources:
```
build/workspace/appends/pantavisor_git.bbappend
build/workspace/appends/lxc-pv_git.bbappend   # Create manually if needed
```

Key pantavisor components:
- `xconnect/` - Service mesh daemon and plugins
- `ctrl/` - REST API control server
- `parser/` - State JSON parsing
- `plugins/` - Container runtime plugins (LXC, etc.)

See `build/workspace/sources/pantavisor/CLAUDE.md` for detailed pantavisor architecture.

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
       "workflows": ["manual", "tag"]
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

## Common Tasks

### Bump pantavisor SRCREV

When updating `SRCREV` in `recipes-pv/pantavisor/pantavisor_git.bb`:

1. **Always verify the commit hash against the actual remote** — squash merges rewrite hashes, so a branch SHA won't match the merged master SHA even if they share the same prefix
2. **Update `PKGV`** to match the latest tag reachable from the new SRCREV (e.g. if latest tag is `026`, set `PKGV = "026+git0+${GITPKGV}"`)

### Add a new example container

1. Create recipe in `recipes-containers/pv-examples/`
2. Add `services.json` (provider) or `args.json` (consumer) in `files/`
3. Build with `--target pv-example-<name>`

### Test xconnect changes

1. Edit `build/workspace/sources/pantavisor/xconnect/`
2. Rebuild with `:kas/with-workspace.yaml`
3. Load new docker image and test with appengine

### Debug container issues

```bash
# Check pantavisor logs (appengine path)
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log

# Check container logs
docker exec pva-test cat /var/pantavisor/storage/logs/0/<container>/lxc/console.log

# Enter container namespace
docker exec -it pva-test pventer -c <container>

# Query xconnect graph
docker exec pva-test pvcontrol graph ls

# Query daemon status
docker exec pva-test pvcontrol daemons ls
```

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

## Supported Yocto Releases

- kirkstone (LTS)
- scarthgap (current)

Layer compatibility defined in `conf/layer.conf`: `LAYERSERIES_COMPAT_meta-pantavisor = "kirkstone scarthgap"`

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

## External Resources

- [Pantavisor Documentation](https://docs.pantahub.com/pantavisor-architecture/)
- [Pantahub Community](https://community.pantavisor.io)
- [Getting Started Guide](https://docs.pantahub.com/before-you-begin/)
