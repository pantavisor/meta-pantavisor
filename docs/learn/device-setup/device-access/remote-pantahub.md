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

## Managing Devices Remotely with Pantahub

Once your device is connected to the internet and registered with Pantahub, you can interact with it from anywhere in the world. Pantahub acts as a central control plane for managing the software lifecycle, viewing logs, and monitoring the status of all your Pantavisor devices.

### 1. Authentication

To interact with your devices remotely, you first need to authenticate the `pvr` CLI tool with Pantahub. 

```bash
pvr login
```

You can verify your current session at any time:

```bash
pvr whoami
```

### 2. Viewing Your Devices

You can list all devices associated with your Pantahub account to see their current status, revision, and metadata:

```bash
pvr device ps
```

This will display a table showing each device's nickname, Pantahub ID, current revision, and update status.

### 3. Remote State Management (OTA Updates)

You do not need to be on the same local network to update your device. With Pantahub, you can simply clone the device's state over the internet, make modifications, and post the changes back.

To clone a remote device state:

```bash
pvr clone https://api.pantahub.com/trails/<DEVICE_ID> my-device-workspace
cd my-device-workspace
```

After making your desired changes (for example, adding a new container or updating a configuration), commit and post the update back to the device:

```bash
pvr add .
pvr commit
pvr post -m "Updating configuration remotely"
```

The device will automatically download and apply the new state as an Over-The-Air (OTA) update.

### 4. Viewing Device Logs Remotely

Pantahub streams logs from your device directly to the cloud, allowing you to troubleshoot without SSH or local access. 

Use the `pvr device logs` command followed by your device's nickname to tail or query logs remotely:

```bash
# View all recent logs for a device
pvr device logs my-device

# Filter logs by a specific container or source
pvr device logs my-device/app.log
pvr device logs my-device/pantavisor.log

# Filter logs by severity level
pvr device logs my-device@ERROR
```

You can even combine filters or specify date ranges to pinpoint issues over a specific timeframe:

```bash
pvr device logs --from="2024-01-01T00:00:00" --to="2024-01-31T23:59:59" my-device/app.log@INFO
```

### 5. Managing Device Metadata

You can attach arbitrary metadata to your devices to organize them (for example, by location or purpose). 

```bash
pvr device set <DEVICE_ID> location=warehouse tier=production
```

To view device details, including its metadata, use:

```bash
pvr device get <DEVICE_NICK>
```

Using Pantahub ensures that no matter where your devices are deployed, you retain complete visibility and control over their software state and operation.
