+++
title = "Device Access"
weight = 10

# SEO Configuration
description = "Quick start guide for setting up Pantavisor Linux on your device. Flash images, configure network, install applications in just a few minutes."
keywords = ["pantavisor quick start", "pantavisor setup", "embedded linux setup", "iot device setup", "raspberry pi pantavisor", "flash pantavisor", "embedded container setup", "pantavisor installation", "iot linux installation"]
meta_description = "Quick Start: Set up Pantavisor Linux on your device in 5 minutes. Complete guide from flashing to installing your first containerized application."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor Quick Start - Device Setup Guide"
og_description = "Get Pantavisor Linux running on your device in 5 minutes. Complete setup guide from flashing to first application installation."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Quick Start - 5 Minute Setup"
twitter_description = "Set up containerized embedded Linux on your device in just 5 minutes"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.9
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/"
+++

A Pantavisor device exposes several access points depending on your connectivity and what you need to do.

| Method | When to use |
|--------|-------------|
| [Serial console](./serial-port/) | First boot, network not yet configured, low-level debugging, debug shell |
| [Local network — SSH](./local-network/) | Day-to-day management once the device is on a network |
| [pvtx web UI](./pvtx-ui/) | Browse container status, view logs, upload container packages without the CLI |
| [Pantahub — remote](./remote-pantahub/) | OTA updates, log streaming, and device management from anywhere |

### Serial Console

The serial console is the lowest-level access path and works without any network configuration. Pantavisor prints a debug shell prompt shortly after boot — pressing **Enter** drops you into a root shell where you can run `lxc-ls`, `pventer`, and `pvcontrol` directly on the device.

### Local Network

Once the device has an IP address (via Ethernet or Wi-Fi), you can reach it over SSH and via `pvr` on your workstation. The `pvr` CLI clones the device state, lets you add or modify containers, and deploys the new revision back over the network. The pvtx web UI is also reachable on port **12368**.

### Pantahub

Devices that are claimed on [Pantahub](https://pantahub.com) can be managed from anywhere. The `pvr` CLI authenticates to Pantahub and lets you clone, modify, and push device state remotely — the device polls for updates and applies them as OTA revisions. Logs are streamed to Pantahub in real time.