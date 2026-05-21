---
title: "Supported Devices"
description: "Table of supported devices"
lead: "Supported Devices"
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 200

# SEO Configuration
keywords: ["pantavisor cli", "pvr cli", "command line tools", "embedded cli", "container cli", "pvcontrol", "pantavisor commands", "embedded development tools", "iot cli tools", "supported devices"]
meta_description: "Supported Devices: Complete reference for Pantavisor supported hardware and command-line tools including PVR CLI and pvcontrol."
author: "Pantacor Ltd"

# Open Graph / Social Media
og_title: "Pantavisor CLI Tools Reference"
og_description: "Complete guide to Pantavisor command-line tools including PVR CLI and essential development workflows."
og_type: "article"
og_image: "/images/logo-pantacor.png"

# Twitter specific
twitter_title: "Pantavisor CLI Tools Guide"
twitter_description: "Essential command-line tools for embedded Linux container development with Pantavisor"
twitter_card: "summary_large_image"

# SEO Settings
robots: "index, follow"
sitemap_priority: 0.8
sitemap_changefreq: "monthly"
canonical_url: "https://www.pantavisor.io/cli-tools/"
---

## Supported Devices

While Pantavisor can run on virtually any device that supports Linux, we offer official, out-of-the-box support for a wide range of popular hardware through our [meta-pantavisor](https://github.com/pantavisor/meta-pantavisor) Yocto layer. This ensures a smooth and tested experience for developers.

## Pre-build images

If you a quickstart, we have a couple of pre-build images ready for testing and exploring Pantavisor. Head to [downloads](downloads).

### Officially Supported Devices

Below is a list of devices and platforms that are officially supported. These are grouped by manufacturer or platform type for easy reference.

### Raspberry Pi Foundation
- raspberrypi-armv8 (e.g., Raspberry Pi 3, 4, 5)
- raspberrypi-armv7 (e.g., Raspberry Pi 2)

### NXP
- imx8qxp-b0-mek
- imx8qxp-mek

### Variscite

- imx8mn-var-som
- imx8mm-var-dart

### Toradex

- colibri-imx6ull

### Google

- Google Coral Dev Board

### Rockchip

- rockchip rk3328 evb
- rockchip rk3399pro evb
- rockchip rock64

### Radxa

- radxa rock5a
- radxa rock5b

### Texas Instruments (TI)

- TI AM62xx EVM
- TI AM62axx EVM
- TI AM65xx EVM
- TI Beaglebone
- TI Beagleplay

### Allwinner / Sunxi

- Banana Pi M2 Berry
- NanoPi R1
- Orange Pi R1
- Orange Pi Zero Plus2 H3
- Orange Pi 3 LTS
- Orange Pi PC Plus
- Orange Pi PC2

### RISC-V

- StarFive VisionFive 2

### Don't See Your Board?

No problem! Pantavisor is designed for portability. If your device can run Linux and has a Board Support Package (BSP), it can be enabled to run Pantavisor. Feel free to reach out to the community or our team for guidance on porting to new hardware.
