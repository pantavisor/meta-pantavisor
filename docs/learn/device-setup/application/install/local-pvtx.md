+++
title = "PVTX"
weight = 42

# SEO Configuration
description = "Install your first application on Pantavisor Linux using PVTX. Step-by-step guide to install Home Assistant from the marketplace."
keywords = ["install pantavisor app", "home assistant install", "pvtx installation", "first application", "pantacor marketplace", "container install", "app installation guide", "embedded app install", "pantavisor applications", "iot app deployment"]
meta_description = "Install Your First Application: Complete guide to installing Home Assistant and other apps on Pantavisor Linux using the PVTX interface."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Install Your First Application on Pantavisor Linux"
og_description = "Learn to install applications like Home Assistant on your Pantavisor Linux device using the PVTX interface."
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

The pvtx web UI lets you upload a container package to a device using only a browser — no `pvr deploy` or direct network access to the pvr endpoint required. You still use the `pvr` CLI on your workstation to build the package, then transfer it via the browser.

**Prerequisites**: `pvr` installed on your workstation ([install guide](../../../cli-tools/pvr-cli/)) and the device reachable on the local network.

---

## 1 — Build the Container Package

On your workstation, create a fresh `pvr` project and add the container you want to install.

```bash
mkdir myapp-pkg
cd myapp-pkg
pvr init
```

Add the container from Docker Hub, setting `--platform` to match your device:

```bash
pvr app add myapp --from myorg/myapp:latest --platform linux/arm64
pvr add .
pvr commit -m "add myapp"
```

Export the project as a `.tar.gz` bundle that pvtx can consume:

```bash
pvr export myapp.tar.gz
```

This archive contains the container's SquashFS rootfs, its LXC config, and the revision metadata.

---

## 2 — Upload via pvtx

Open a browser and navigate to the device's local web UI:

```
http://<device-ip>:12368/app
```

1. Click **"Begin Transition"** to open the update panel.
2. Drag and drop `myapp.tar.gz` into the upload area, or use the file picker.

![pvtx transaction upload](/images/pvtx-ui-transaction.png)

3. Click **"Commit Transaction"** to apply the change.

Pantavisor writes the uploaded container as a new pending revision and reboots. If the revision boots cleanly, it becomes the new permanent state.

---

## 3 — Verify

After the device reboots, check from the serial console or SSH:

```bash
lxc-ls -f
```

The new container should appear as `RUNNING`. You can also confirm in the pvtx UI revision history at `http://<device-ip>:12368/app`.

---

**Note**: If a debug shell appears on the serial console after the reboot, the device is waiting for confirmation before committing. Follow the on-screen instructions to proceed or roll back..