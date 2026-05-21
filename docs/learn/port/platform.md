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

## How to Add a New `kas` Platform to `meta-pantavisor`

In the `meta-pantavisor` project, a **`kas` platform** file is a YAML configuration that defines a complete set of Yocto layers required for a specific family of devices. This typically includes vendor-provided Board Support Package (BSP) layers, as well as any other custom or required layers.

This system simplifies build configurations by grouping all necessary layers into a single, reusable file.

> **Before You Start:** We already have a substantial number of platforms defined in `meta-pantavisor`. Before creating a new one, please check if a suitable platform already exists:
>
> * [**View Existing Platforms**](https://github.com/pantavisor/meta-pantavisor/tree/master/kas/platforms)

---

### Example: Adding the Toradex NXP Platform

For this guide, we'll walk through adding support for the vendor **Toradex** and their **NXP-based** boards.

#### 1. Identify Vendor Layers

First, you must identify all the Yocto layers the vendor requires for the target boards. A good place to start is the vendor's official documentation.

In this case, Toradex provides this information in their [developer documentation](https://developer.toradex.com/linux-bsp/os-development/reference-documentation/#manifests). From their `repo` manifest, we can see the required layers for NXP boards are:

* `meta-toradex-bsp-common`
* `meta-toradex-nxp`
* `meta-freescale`
* `meta-freescale-distro`
* `meta-freescale-3rdparty`

#### 2. Create the Platform YAML File

With the layer information, we can create our new platform file.

1.  Create a new file in the `kas/platforms/` directory. We will name it `toradex-nxp.yaml`.
2.  A key feature of `kas` is reusability. Looking at the required layers, we see that the Freescale layers are already defined in the existing `freescale.yaml` platform file. We can **include** this file to avoid duplicating definitions.
3.  Add the new, Toradex-specific layers under the `repo:` key.

Add the following content to `toradex-nxp.yaml`:

```yaml
header:
  version: 16
  includes:
    # Include the existing freescale layers to avoid duplication
    - kas/platforms/freescale.yaml

# Add the new Toradex-specific layers
repo:
  meta-toradex-bsp-common:
    path: layers/meta-toradex-bsp-common
    # Note: URLs are just plain strings, do not use Markdown
    url: "https://git.toradex.com/meta-toradex-bsp-common.git"
    branch: scarthgap-7.x.y

  meta-toradex-nxp:
    path: layers/meta-toradex-nxp
    url: "https://git.toradex.com/meta-toradex-nxp.git"
    branch: scarthgap-7.x.y
```

> **Important**: Always make sure the path, url, and branch are correct. The branches should match the Yocto release you are targeting (e.g., scarthgap).

#### 3. Add Platform-Specific Configuration (Optional)

Some platforms require specific variables to be set in the Yocto `build/conf/local.conf` file. You can inject these settings directly from your platform file using the `local_conf_header` key.

For example, the raspberrypi.yaml platform needs to add several configuration flags:

```
LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
RPI_USE_U_BOOT = "1"
ENABLE_UART = "1"
```

This is done by adding the following to the `raspberrypi.yaml` file:

```yaml
local_conf_header:
  platform-raspberrypi: |
    LICENSE_FLAGS_ACCEPTED += "synaptics-killswitch"
    RPI_USE_U_BOOT = "1"
    ENABLE_UART = "1"
```
If your new platform (like the Toradex NXP) requires similar default settings, you can add a `local_conf_header` block to your `toradex-nxp.yaml` file in the same way.