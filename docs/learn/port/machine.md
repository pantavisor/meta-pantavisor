+++
title = "Device specification"
weight = 3

# SEO Configuration
description = "Learn about device machine specifications for porting Pantavisor Linux. Guide to hardware configuration and board support packages."
keywords = ["pantavisor machine", "device specification", "board support", "hardware configuration", "pantavisor porting", "machine config", "embedded hardware", "bsp configuration", "device porting", "yocto machine"]
meta_description = "Device Specification: Guide to machine configurations and hardware specifications for porting Pantavisor Linux to new devices."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor - Device Specification"
og_description = "Learn about device machine specifications for porting Pantavisor Linux to new hardware platforms."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Device Specification"
twitter_description = "Guide to machine specifications for porting Pantavisor Linux to new devices"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/port/machine/"
+++

A **machine file** in `kas/machines/` binds a platform (its set of BSP layers) to a specific Yocto `MACHINE` name and adds any device-specific BitBake configuration.

> **Before creating a new machine file**, check whether your board already has one: [`kas/machines/`](https://github.com/pantavisor/meta-pantavisor/tree/master/kas/machines). Existing machines include Raspberry Pi variants, Variscite iMX8, Toradex Verdin/Colibri, NXP MEK, Rockchip, RISC-V VisionFive2, and QEMU targets.

---

## Example: Adding the Verdin i.MX 8M Mini

### 1 — Find the Vendor Machine Name

The Yocto `MACHINE` variable must match a `.conf` file in the vendor's BSP layer. In the Toradex layers (`meta-toradex-nxp`), machine configs live under `conf/machine/`. The file `verdin-imx8mm.conf` gives us the machine name `verdin-imx8mm`.

### 2 — Create the Machine YAML File

Create `kas/machines/verdin-imx8mm.yaml`:

```yaml
header:
  version: 16
  includes:
    - kas/platforms/toradex.yaml   # the platform that provides the BSP layers

machine: "verdin-imx8mm"
```

### 3 — Add Device-Specific Variables (if needed)

Use `local_conf_header` to override BitBake variables for this specific board variant. For example, the Verdin iMX8MM Wi-Fi variant needs a specific device tree:

```yaml
header:
  version: 16
  includes:
    - kas/platforms/toradex.yaml

machine: "verdin-imx8mm"

local_conf_header:
  platform-verdin-imx8mm: |
    UBOOT_DTB_NAME = "imx8mm-verdin-wifi-dev.dtb"
    PV_FLASH_README = "docs/flashing/boards/verdin-imx8mm.md"
```

---

## Register the Machine for CI

After creating the machine YAML, add an entry to `.github/machines.json` so it appears in CI workflows:

```json
{
  "config": "kas/machines/verdin-imx8mm.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:kas/build-configs/build-base-starter.yaml",
  "name": "verdin-imx8mm",
  "workflows": ["manual", "tag"]
}
```

Then regenerate the GitHub Actions workflow files and commit both files together:

```bash
.github/scripts/makeworkflows
git add .github/machines.json .github/workflows/
git commit -m "feat: add verdin-imx8mm machine"
```

---

## Machine File Structure

| Key | Purpose |
|-----|---------|
| `header.version` | KAS format version (use `16`) |
| `header.includes` | Platform YAML to pull in (provides BSP layers) |
| `machine` | Yocto `MACHINE` name matching the vendor's `.conf` file |
| `local_conf_header` | Device-specific BitBake variables |

Once the machine file is in place, proceed to [Building](../kas/) to run the build and flash the image.