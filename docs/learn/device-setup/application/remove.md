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

You can remove an app or container from a Pantavisor-enabled device using the `pvr` command-line interface (CLI). The process involves cloning the device's current state, removing the app's directory locally, and then posting the new revision back to the device.

---

## Step 1: Clone the Device State

First, if you haven't already, clone the device's configuration to your local machine. This creates a directory that mirrors the device's software components.

Run the `pvr clone` command, replacing `<device-ip>` with your device's address and `my-device` with your preferred local directory name.

```bash
pvr clone <device-ip> my-device
```

Navigate into the newly created directory:

```bash
cd my-device
```

Inside, you will find a file structure representing your device's components, which should look similar to this:

```bash
.
├── bsp/
├── _config/
├── device.json
├── os/
├── pvr-sdk/
├── pvwificonnect/
└── _sigs/
```

## Step 2: Remove the App's Directory

To remove an app, simply use `pvr app` utility. For this example, we'll remove the pvwificonnect app.

pvr app rm pvwificonnect

This action tells Pantavisor that this component should no longer be part of the device's state.

## Step 3: Commit and Post the New Revision

Next, you need to stage and commit this change. This process is similar to using Git.

1. Stage the change (the deletion of the directory):

```bash
pvr add .
```

2. Commit the change with a descriptive message:

```bash
pvr commit -m "Removed the pvwificonnect app"
```

3. Finally, post the new revision to the device. This uploads your local changes and instructs the device to update itself.

```bash
pvr post
```

## Step 4: Finalizing the Update

After you run `pvr post`, the Pantavisor agent on the device will download and apply the new revision. It will stop and remove the container you deleted. Once the update is successfully applied, the device will reboot with the new configuration, and the app will be gone.
