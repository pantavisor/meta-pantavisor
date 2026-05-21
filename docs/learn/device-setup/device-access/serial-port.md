---
title: "Serial Console"
weight: 2

# SEO Configuration
description: "Configure WiFi and ethernet network connectivity for Pantavisor Linux devices. Complete guide for getting your device online."
keywords: ["pantavisor network setup", "wifi configuration", "ethernet setup", "embedded network", "iot connectivity", "device network config", "pantavisor wifi", "embedded linux network", "device internet connection", "iot network setup"]
meta_description: "Network Setup: Configure WiFi and ethernet connectivity for your Pantavisor Linux device. Step-by-step guide to get your device online."
author: "Pantacor Ltd"

# Open Graph / Social Media
og_title: "Pantavisor Network Setup - WiFi and Ethernet Configuration"
og_description: "Configure network connectivity for your Pantavisor Linux device. Complete guide for WiFi and ethernet setup."
og_type: "article"
og_image: "/images/logo-pantacor.png"

# Twitter specific
twitter_title: "Pantavisor Network Setup Guide"
twitter_description: "Configure WiFi and ethernet connectivity for your embedded Linux device"
twitter_card: "summary_large_image"

# SEO Settings
robots: "index, follow"
sitemap_priority: 0.8
sitemap_changefreq: "monthly"
canonical_url: "https://www.pantavisor.io/learn/device-setup/network-setup/"
---

## Accessing Your Pantavisor Device via Serial Port

The most reliable way to get started with a new Pantavisor device is by using a serial port for initial access. This direct, hardware-based connection lets you configure network settings and troubleshoot issues before you connect over a network.

This method requires a USB-to-TTY converter cable to connect your computer to the device's serial pins.

## Step 1: Connect the Hardware

First, connect the serial cable to your computer and the corresponding pins on your device (TX/RX/GND).

Next, you'll need a terminal emulator on your computer to open the serial console. `Minicom` is a common tool for this on Linux. To open the console, use the following command:

```
sudo minicom -D /dev/ttyUSB0
```

Make sure to replace /dev/ttyUSB0 with the correct serial device name for your board.

## Step 2: Boot and Access the Debug Shell
When you power on your device, you'll see a stream of boot messages from the bootloader and kernel. Eventually, you will see the Pantavisor banner.

```bash
_____           _              _
| ___ \         | |            (_)
| |_/ /_ _ _ __ | |_ __ ___   ___ ___  ___  _ __
|  __/ _` | '_ \| __/ _` \ \ / / / __|/ _ \| '__|
| | | (_| | | | | || (_| |\ V /| \__ \ (_) | |
\_|  \__,_|_| |_|\__\__,_| \_/ |_|___/\___/|_|

Pantavisor (TM) (devtool-base-23-gf0694b9-250820 | Pantavisor Remix Distro (019)) - pantavisor.io
cmdline: earlyprintk panic=3 root=/dev/ram rootfstype=ramfs rdinit=/usr/bin/pantavisor console=ttymxc0,115200 pv_try= pv_rev=0 panic=2 pv_quickboot

To access the debug shell, press <ENTER>.
To exit the shell, type 'exit' or press CTRL+d.
Press <ENTER> again to reopen the shell.
Useful commands:
    * lxc-ls                 :list available containers.
    * pventer -c <CONTAINER> :to access the shell of a container.

```

At this point, you can access the Debug Shell by pressing Enter. This gives you immediate access to a low-level command line on the device.

## Debug Shell

The Debug Shell is a core feature that provides early access to your device's console, bypassing the need for a network. It is enabled by default in all official Pantavisor starter images, allowing you to begin troubleshooting or configuring your device as soon as you boot it.
