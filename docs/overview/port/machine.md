---
title: Device specification
sidebar_position: 3
description: Learn about device machine specifications for porting Pantavisor Linux. Guide to hardware configuration and board support packages.
---

A **machine file** in `kas/machines/` binds a platform (its set of BSP layers) to a specific Yocto `MACHINE` name and adds any device-specific BitBake configuration.

> **Before creating a new machine file**, check whether your board already has one: [`kas/machines/`](https://github.com/pantavisor/meta-pantavisor/tree/master/kas/machines). Existing machines include Raspberry Pi variants, Variscite iMX8, Toradex Verdin/Colibri, NXP MEK, Rockchip, RISC-V VisionFive2, and QEMU targets.

---

## Worked Example: the Verdin i.MX 8M Mini

The layer already ships `kas/machines/verdin-imx8mm.yaml` — it makes a good
template for a new machine file. Here is how it is put together.

### 1 — Find the Vendor Machine Name

The Yocto `MACHINE` variable must match a `.conf` file in the vendor's BSP layer. In the Toradex layers (`meta-toradex-nxp`), machine configs live under `conf/machine/`. The file `verdin-imx8mm.conf` gives us the machine name `verdin-imx8mm`.

### 2 — Bind the Platform and Machine Name

The core of `kas/machines/verdin-imx8mm.yaml` (excerpt):

```yaml
header:
  version: 14
  includes:
    - kas/platforms/toradex.yaml   # the platform that provides the BSP layers

machine: verdin-imx8mm
```

### 3 — Add Device-Specific Variables (if needed)

Use `local_conf_header` to override BitBake variables for the specific board variant. The Verdin iMX8MM Wi-Fi variant, for example, needs a specific device tree (excerpt):

```yaml
local_conf_header:
  platform-verdin-imx8mm: |
    UBOOT_DTB_NAME = "imx8mm-verdin-wifi-dev.dtb"
    PV_FLASH_README = "docs/flashing/boards/verdin-imx8mm.md"
```

The shipped file goes further — Wi-Fi machine features, firmware packages, kernel module autoloads, and TEZI image classes — read it in full for a real-world reference.

---

## Register the Machine for CI

To put a machine into the CI build matrix, you would add an entry like this to `.github/machines.json` (the verdin-imx8mm is not currently registered there):

```json
{
  "config": "kas/machines/verdin-imx8mm.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:kas/build-configs/build-base-starter.yaml",
  "name": "verdin-imx8mm",
  "workflows": ["manual", "tag"]
}
```

Then regenerate the workflow files with `.github/scripts/makeworkflows`, generate the pinned release lockfile (`kas/build-configs/release/<machine>-scarthgap.yaml`) with `.github/scripts/makemachines`, and commit everything together — see the [CI overview](../ci/overview.md) for the full process.

---

## Machine File Structure

| Key | Purpose |
|-----|---------|
| `header.version` | KAS format version (existing files use `14`–`16`; use `16` for new files) |
| `header.includes` | Platform YAML to pull in (provides BSP layers) |
| `machine` | Yocto `MACHINE` name matching the vendor's `.conf` file |
| `local_conf_header` | Device-specific BitBake variables |

Once the machine file is in place, proceed to [Building](./kas.md) to run the build and flash the image.