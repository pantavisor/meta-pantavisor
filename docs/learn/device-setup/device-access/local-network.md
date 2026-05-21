---
title: "Local Network"
weight: 3

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

## Accessing Your Device Over a Network
Once you've used the serial port for initial setup, you can configure your device to connect to a network for more convenient access. This will enable remote login via SSH or management through Pantahub.

## Connect to a Network
The simplest way to connect to a network is by plugging an Ethernet cable directly from your device to your router. The device will automatically get an IP address via DHCP.

After connecting, you can find the device's IP address from the serial console by running a command like `ifconfig`. Look for the `inet addr` field to find the IP address.

For example:
```bash
eth0      Link encap:Ethernet  HWaddr B8:27:EB:CA:26:F3
          inet addr:192.168.1.102  Bcast:192.168.1.255  Mask:255.255.255.0
```

## Local Network Access via SSH
With the device's IP address, you can connect to it via SSH from any computer on the same local network. The default credentials are:

Username: `root`

Password: `pantavisor`

To connect, simply run:

```bash
ssh root@[device-ip]
```

When you connect via SSH, you are accessing the pvr-sdk container running on the device.

## Security Notice
Before deploying your device, it's crucial to secure it. You should change the default password and set up SSH keys to protect against unauthorized access.

Change the Default Password: Use the `chpasswd` command from the terminal to set a new password for the root user.

Add Your Public SSH Key: For secure, password-less login, add your public key to the authorized_keys file.

```bash
mkdir -p ~/.ssh
echo "your-public-key-here" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```
After setting up SSH keys, you can connect securely without needing a password.