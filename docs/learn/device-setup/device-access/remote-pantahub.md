---
title: "Remote Access via Pantahub"
weight: 5

# SEO Configuration
description: "Learn how to access, monitor, and update your Pantavisor devices remotely using Pantahub and the PVR CLI tool."
keywords: ["pantavisor remote access", "pantahub", "pvr cli", "iot remote management", "embedded linux updates", "ota updates"]
meta_description: "Remote Access: Learn how to manage your Pantavisor devices from anywhere using Pantahub and the PVR CLI."
author: "Pantacor Ltd"

# Open Graph / Social Media
og_title: "Remote Device Management with Pantahub"
og_description: "Access, monitor, and update your Pantavisor devices remotely using Pantahub."
og_type: "article"
og_image: "/images/logo-pantacor.png"

# Twitter specific
twitter_title: "Pantavisor Remote Access Guide"
twitter_description: "Manage your embedded Linux devices remotely over Pantahub"
twitter_card: "summary_large_image"

# SEO Settings
robots: "index, follow"
sitemap_priority: 0.8
sitemap_changefreq: "monthly"
canonical_url: "https://www.pantavisor.io/learn/device-setup/device-access/remote-pantahub/"
---

Once a device is claimed on Pantahub and connected to the internet, you can manage it from anywhere using the `pvr` CLI. The device polls Pantahub for new revisions and applies OTA updates automatically — no local network access required.

## 1 — Claim the Device

Before remote management is possible the device must be registered. Read the device ID and challenge token from the serial console:

```bash
cat /pv/device-id
cat /pv/challenge
```

Log in to [hub.pantacor.com](https://hub.pantacor.com), go to **Claim Device**, and enter both values. Once claimed the device appears in your account and its online status updates in real time.

## 2 — Authenticate pvr

On your workstation, log in to Pantahub:

```bash
pvr login
```

Verify the session:

```bash
pvr whoami
```

## 3 — View Your Devices

List all devices in your account:

```bash
pvr device ps
```

This shows each device's nickname, Pantahub ID, current revision, and update status.

## 4 — Remote OTA Updates

Clone the device's state over the internet, make changes, and deploy back:

```bash
pvr clone https://api.pantahub.com/trails/<device-id> my-device
cd my-device

# Make changes — add a container, edit run.json, update config overlays
pvr app add myapp --from myorg/myapp:latest --platform linux/arm64
pvr add .
pvr commit -m "add myapp"
pvr deploy trails/0 .
```

Pantahub queues the new revision. The device downloads only the changed objects (not a full image) and applies the update on the next poll cycle. Monitor progress from the device dashboard on hub.pantacor.com or with:

```bash
pvr device get <device-nick>
```

## 5 — View Device Logs Remotely

Pantahub streams logs from the device to the cloud. Use `pvr device logs` to read them without SSH:

```bash
# All recent logs
pvr device logs my-device

# Filter by container or source
pvr device logs my-device/pantavisor.log
pvr device logs my-device/sensor-app.log

# Filter by severity
pvr device logs my-device@ERROR
```

## 6 — Device Metadata

Attach labels to devices to organize your fleet:

```bash
pvr device set <device-id> location=warehouse tier=production
pvr device get <device-nick>
```
