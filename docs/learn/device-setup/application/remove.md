+++
title = "Remove applications"
weight = 42

# SEO Configuration
description = "Monitor and manage installed applications on Pantavisor Linux. Learn to check status, start/stop apps, and view application details."
keywords = ["view pantavisor apps", "application status", "manage containers", "pvr app list", "app monitoring", "container management", "installed applications", "application control", "pantavisor management", "device app status"]
meta_description = "View Installed Applications: Monitor and manage your Pantavisor Linux applications. Check status, control app lifecycle, and view details."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "View and Manage Installed Applications on Pantavisor"
og_description = "Learn to monitor and manage installed applications on your Pantavisor Linux device. Complete guide to application lifecycle management."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Manage Pantavisor Applications"
twitter_description = "Monitor and control your containerized applications on embedded Linux devices"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.7
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/view-installed-applications/"
+++

Removing an application follows the same revision workflow as adding one: remove the container from your local `pvr` checkout, commit, and deploy. Pantavisor stops the container and removes it from the trail on the next boot.

---

## Step 1 — Clone the Device State

If you do not already have a local checkout, clone the device:

```bash
pvr clone http://<device-ip>:12368/cgi-bin/pvr my-device
cd my-device
```

The directory mirrors the device's current revision:

```
my-device/
├── bsp/
├── network/
├── sensor-app/
├── my-old-app/           ← the container you want to remove
├── _config/
├── device.json
└── _sigs/
```

## Step 2 — Remove the Container

Use `pvr app rm` to remove the container from the local state:

```bash
pvr app rm my-old-app
```

This deletes the container's directory from your checkout and stages the removal.

## Step 3 — Commit and Deploy

Stage any remaining changes, commit, and deploy to the device:

```bash
pvr add .
pvr commit -m "remove my-old-app"
pvr deploy trails/0 .
```

## Step 4 — What Happens on the Device

When Pantavisor receives the new revision it:

1. Stops the removed container
2. Writes the new revision to `/trails/`
3. Reboots into the new state

After the reboot, `pvcontrol container ls` and `lxc-ls -f` will no longer show the removed container. The previous revision (with the container) is kept in the trail and can be restored by rolling back if needed.
