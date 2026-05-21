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

### **Installing an App with the `pvr` CLI**

The `pvr` Command Line Interface (CLI) is the **fastest** and **easiest** way to manage changes on a Pantavisor-powered device. This guide will walk you through adding a new containerized app, specifically Tailscale, to your device.

---

#### **1. Cloning the Device**

First, you need to clone the device's current state to your local machine. This process requires that your device is on the same local network and that you know its IP address.

To clone the device, use the following command:

```bash
pvr clone <DEVICE_IP> mydevice
```

This command clones the device's entire state, including all running containers, their configurations, and any associated files. The device's Board Support Package (BSP) component is also cloned, ensuring a complete and accurate replica of your device's software environment.


#### 2. Adding the New Container

Now that you have a local copy of the device's state, you can add the new container. This example adds the Tailscale container.

Use the `pvr app add` command to add the container from its source image:

```bash
pvr app add tailscale --from tailscale/tailscale --platform linux/arm64
```

Next, stage the newly added files to prepare them for a commit:

```bash
pvr add .
```

#### 3. Committing the Changes

To verify that your changes have been staged correctly, you can use the `pvr status` command:

```bash
pvr status
```

The output will look similar to this, showing the new files for the Tailscale app staged for a commit:

```bash
A tailscale/lxc.container.conf
A tailscale/root.squashfs
A tailscale/root.squashfs.docker-digest
```
Once you've confirmed the status, commit the changes with a descriptive message:

```bash
pvr commit -m "Add Tailscale container"
```

This command creates a new **revision** of your device's configuration on your local machine.

#### 4. Deploying to the Device

To deploy the new revision to your device, use the `pvr post` command:

```bash
pvr post
```

This command pushes the new revision to the target device. The device will automatically download the new container and trigger a reboot to apply the changes.

### 5. Verifying the Installation

After the device reboots, you can verify that the new container is running. If you have a serial console connected to the device, you can use the following command to list all running containers:

```bash
lxc-ls
```

This command will display a list of all containers, including your newly installed Tailscale app, confirming that the installation was successful. You can also check the running containers on local pvtx UI that on `http:<DEVICE IP>:12368/app`