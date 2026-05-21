+++
title = "Porting Pantavisor"
weight = 50

# SEO Configuration
description = "Troubleshooting guide for Pantavisor Linux. Find solutions to common issues, connectivity problems, and app management questions."
keywords = ["pantavisor troubleshooting", "pantavisor problems", "embedded linux issues", "connectivity issues", "app problems", "pantavisor faq", "device troubleshooting", "pantavisor support", "embedded troubleshooting", "iot device issues"]
meta_description = "Troubleshooting: Complete guide to solving common Pantavisor Linux issues. Solutions for connectivity, app management, and system problems."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor Linux Troubleshooting Guide"
og_description = "Find solutions to common Pantavisor Linux issues. Complete troubleshooting guide for connectivity, apps, and system problems."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Troubleshooting Guide"
twitter_description = "Solve common issues with your Pantavisor Linux device. Complete troubleshooting and FAQ guide"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/troubleshooting/"

[params]
  menuPre = '<i class="fa-fw fas fa-layer-group"></i> '
+++

## Development and Porting Guide

### Our Development Setup

Our build system is based on the Yocto Project. We use several key tools to create flashable images and system components for Pantavisor.

- **meta-pantavisor**: This is our custom Yocto layer that contains the core recipes, configurations, and logic required to build Pantavisor-enabled systems.

- **KAS**: We use [KAS](https://github.com/siemens/kas) to manage the build environment. It handles fetching the correct layers, setting up the configuration, and launching the build process.

- **Bitbake**: This is the core build engine for the Yocto Project. KAS provides a simplified interface for configuring and running bitbake.

For a deeper dive into our Yocto configuration and build settings, please refer to the main [Yocto Session](/content/learn/build/).

### Porting a New Device

This guide will walk you through the process of adding support for a new device, enabling it to run Pantavisor and its related software.

### Porting Process Overview

The process for porting a new device generally follows these three main steps:

- **Add Platform Layers**: Integrate the necessary BSP (Board Support Package) layers for your specific hardware.

- **Add Machine Configuration**: Define a new machine configuration file (.conf) that specifies the device's architecture, kernel, bootloader, and other hardware-specific details.

- **Tweak KAS Configuration**: Adjust the meta-pantavisor KAS configuration files to include your new machine and any required layer modifications for that target.

In general, this process is straightforward. Many platforms available on the market are already supported in `meta-pantavisor`. The bulk of the work is typically in adding the specific machine (device) configuration and making the necessary tweaks for your target.