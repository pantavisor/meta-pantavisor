+++
title = "Device platform"
weight = 2

# SEO Configuration
description = "Learn about Pantavisor device platforms. Guide to platform configuration, layers, and integration for embedded Linux devices."
keywords = ["pantavisor platform", "device platform", "platform configuration", "pantavisor layers", "embedded platform", "linux platform", "platform porting", "device integration", "yocto platform", "pantavisor distro"]
meta_description = "Device Platform: Guide to platform configuration and integration for porting Pantavisor Linux to new device platforms."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor - Device Platform"
og_description = "Learn about Pantavisor device platform configuration and integration for embedded Linux devices."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Device Platform"
twitter_description = "Guide to device platform configuration for porting Pantavisor Linux"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/port/platform/"
+++

A **platform file** in `kas/platforms/` declares the set of Yocto/OE layers required for a family of devices. Platform files are shared across multiple machine configurations — for example, `freescale.yaml` is included by both `nxp.yaml` and `toradex.yaml`.

> **Before creating a new platform file**, check whether a suitable one already exists: [`kas/platforms/`](https://github.com/pantavisor/meta-pantavisor/tree/master/kas/platforms). Existing platforms include `freescale.yaml`, `toradex.yaml`, `raspberrypi.yaml`, `rockchip.yaml`, `sunxi.yaml`, `ti.yaml`, and `variscite.yaml`.

---

## Example: Adding a Toradex NXP Platform

### 1 — Identify the Vendor Layers

Consult the vendor's documentation or BSP manifest to find the required Yocto layers. For Toradex NXP boards the required layers are:

- `meta-toradex-bsp-common`
- `meta-toradex-nxp`
- `meta-freescale`, `meta-freescale-distro`, `meta-freescale-3rdparty` (already in `freescale.yaml`)

### 2 — Create the Platform YAML

Create `kas/platforms/toradex-nxp.yaml`. Use `header.includes` to reuse the existing `freescale.yaml` rather than duplicating the Freescale layer definitions:

```yaml
header:
  version: 16
  includes:
    - kas/platforms/freescale.yaml   # reuse existing Freescale layers

repos:
  meta-toradex-bsp-common:
    path: layers/meta-toradex-bsp-common
    url: "https://git.toradex.com/meta-toradex-bsp-common.git"
    branch: scarthgap-7.x.y

  meta-toradex-nxp:
    path: layers/meta-toradex-nxp
    url: "https://git.toradex.com/meta-toradex-nxp.git"
    branch: scarthgap-7.x.y
```

Branches must match the Yocto release you are targeting (`scarthgap` or `kirkstone`).

### 3 — Add Platform-Level BitBake Variables (if needed)

Use `local_conf_header` to inject variables into `build/conf/local.conf` for all machines that include this platform. For example, the `raspberrypi.yaml` platform enables U-Boot and UART:

```yaml
local_conf_header:
  platform-raspberrypi: |
    LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
    RPI_USE_U_BOOT = "1"
    ENABLE_UART = "1"
```

Add a `local_conf_header` block to your platform file if your vendor BSP requires default configuration flags.

---

## Platform File Structure

| Key | Purpose |
|-----|---------|
| `header.version` | KAS format version (use `16` for current releases) |
| `header.includes` | Other platform YAML files to include (for layer reuse) |
| `repos` | Git repositories for the vendor BSP layers |
| `local_conf_header` | Variables to append to `build/conf/local.conf` |

Once the platform file exists, create a [machine file](../machine/) to target a specific board.