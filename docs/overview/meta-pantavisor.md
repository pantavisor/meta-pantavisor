# meta-pantavisor Overview

meta-pantavisor is the Yocto/OpenEmbedded layer that builds Pantavisor-based BSP images for embedded Linux products. It provides recipes, BitBake classes, and KAS configurations for producing initramfs images and container pvrexport bundles.

## Directory Structure

```
meta-pantavisor/
├── classes/                    # BitBake classes
├── conf/                       # Layer and distro configuration
│   └── multiconfig/            # Per-multiconfig TMPDIR settings
├── dynamic-layers/             # Conditional recipes for other layers
├── kas/                        # KAS configuration fragments
│   ├── machines/               # Per-machine configurations
│   └── platforms/              # Platform-specific layer includes
├── recipes-containers/
│   └── pv-examples/            # Example containers for xconnect testing
├── recipes-pv/                 # Core pantavisor recipes
│   ├── images/                 # Appengine and BSP image recipes
│   ├── pantavisor/             # Pantavisor runtime
│   └── pvr/                   # PVR tool
├── recipes-devtools/           # Development tools (json-sh, fdisk)
└── wic/                        # WIC disk image layout files
```

## Key Recipes

| Recipe | Description |
|--------|-------------|
| `recipes-pv/pantavisor/pantavisor_git.bb` | Core Pantavisor runtime (C, cmake-based) |
| `recipes-pv/images/pantavisor-initramfs.bb` | Initramfs image |
| `recipes-pv/images/pantavisor-bsp.bb` | BSP image (generates pvrexport bundles) |
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

## PANTAVISOR_FEATURES

Controls which optional Pantavisor components are compiled in and installed. Defined in `pvbase.bbclass`:

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
| `rngdaemon` | Random number generator daemon |
| `squash-lz4` | LZ4 squashfs compression |
| `squash-zstd` | Zstd squashfs compression |
| `rpi-tryboot` | Raspberry Pi A/B boot partition support |
| `bootchartd` | Boot timing analysis (writes to `/`; use `rdinit=/sbin/bootchartd`) |

**Default**: `dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect`

### The `+=` vs `:append` Pitfall

`pvbase.bbclass` sets defaults via `??=` (weak default operator):

```bitbake
PANTAVISOR_FEATURES ??= " dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect "
```

In distro includes, you **must** use `:append` or `:remove` — never `+=`:

```bitbake
# WRONG — clobbers ??= defaults, silently drops xconnect, pvcontrol, rngdaemon
PANTAVISOR_FEATURES += "appengine"

# CORRECT — preserves ??= defaults and appends
PANTAVISOR_FEATURES:append = " appengine"
```

## Supported Yocto Releases

| Release | Status |
|---------|--------|
| scarthgap | Current |
| kirkstone | LTS |

Layer compatibility is declared in `conf/layer.conf`:
```
LAYERSERIES_COMPAT_meta-pantavisor = "kirkstone scarthgap"
```
