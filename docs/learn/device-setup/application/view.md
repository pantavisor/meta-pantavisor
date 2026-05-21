+++
title = "View Installed Applications"
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

You can check which applications (containers) are running on your Pantavisor-enabled device using two primary methods: the command-line interface or the local web UI.

## Using the Command-Line Interface (CLI)

This is the most direct way to see your running containers.

Access the serial console of your target device.

Run the following command:

```bash
lxc-ls
```

This command will display a list of all currently running containers. For example:

```
os
pvr-sdk
pvwificonnect
```

## Using the Web User Interface (pvtx)

You can also view the running applications from the device's local web UI, known as pvtx.

Open a web browser and navigate to `http://<device-ip>:12368/app`, replacing `<device-ip>` with your device's actual IP address.

On the homepage, locate the collapsible table which lists all running applications on the device.

![list of containers](/images/pvtx-ui-containers.png)