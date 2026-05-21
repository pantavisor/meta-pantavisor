+++
title = "PVR"
weight = 41

# SEO Configuration
description = "Install your first application on Pantavisor Linux using PVR CLI. Step-by-step guide to install Home Assistant from the marketplace."
keywords = ["install pantavisor app", "home assistant install", "pvr cli installation", "first application", "pantacor marketplace", "container install", "app installation guide", "embedded app install", "pantavisor applications", "iot app deployment"]
meta_description = "Install Your First Application: Complete guide to installing Home Assistant and other apps on Pantavisor Linux using the PVR CLI."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Install Your First Application on Pantavisor Linux"
og_description = "Learn to install applications like Home Assistant on your Pantavisor Linux device using the PVR CLI."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Install Apps on Pantavisor Linux"
twitter_description = "Step-by-step guide to installing your first application on embedded Linux with containers"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/install-first-application/"
+++

The `pvr` CLI lets you add a Docker Hub image as a Pantavisor container, commit the change locally, and deploy it to the device over the local network — all without touching the device directly.

**Prerequisites**: `pvr` installed on your workstation ([install guide](../../../cli-tools/pvr-cli/)) and the device reachable on the local network.

---

## 1 — Clone the Device

Clone the device's current revision to your workstation. Pantavisor exposes its state over HTTP on port 12368.

```bash
pvr clone <device-ip> mydevice
cd mydevice
```

The checkout mirrors the live device state — all containers, their rootfs images, LXC configs, and manifests.

## 2 — Add the New Container

Use `pvr app add` to pull a Docker Hub image and convert it to a Pantavisor container. Specify `--platform` to match your device architecture.

```bash
# ARM64 device (e.g. Raspberry Pi 4, iMX8)
pvr app add tailscale --from tailscale/tailscale --platform linux/arm64

# ARM32 device (e.g. iMX6)
pvr app add tailscale --from tailscale/tailscale --platform linux/arm/v7
```

`pvr app add` pulls the image, converts it to a SquashFS rootfs, and creates the container's directory with:

```
tailscale/
├── root.squashfs               ← container filesystem
├── root.squashfs.docker-digest ← image digest for update tracking
└── lxc.container.conf          ← LXC runtime configuration
```

## 3 — Stage and Commit

Check what was added:

```bash
pvr status
```

Expected output:

```
A tailscale/lxc.container.conf
A tailscale/root.squashfs
A tailscale/root.squashfs.docker-digest
```

Stage and commit the new revision:

```bash
pvr add .
pvr commit -m "add Tailscale container"
```

## 4 — Deploy to the Device

Push the new revision to the device:

```bash
pvr deploy trails/0 .
```

Pantavisor downloads the new container objects, writes them as a pending revision, and reboots. If the revision boots cleanly, it becomes the new permanent state.

## 5 — Verify

After the device reboots, confirm the container is running:

```bash
# From the device console (serial or SSH)
lxc-ls -f

# Or via pvcontrol
pvcontrol container ls
```

The new container should show as `RUNNING`. You can also check from the pvtx web UI at `http://<device-ip>:12368/app`.
