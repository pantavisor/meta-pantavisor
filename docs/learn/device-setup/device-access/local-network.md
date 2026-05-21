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

Once the device has an IP address, you can reach it over SSH, interact with it via `pvr` from your workstation, and browse its pvtx web UI.

## Connect to a Network

**Ethernet**: Plug an Ethernet cable into the device and your router. The device obtains an IP via DHCP automatically.

**Wi-Fi**: Configure the wireless network from the serial console or by pre-configuring the network container before flashing.

## Find the Device IP

From the serial console debug shell:

```bash
ip addr show eth0
# or
ifconfig eth0
```

Look for the `inet` line — for example `inet 192.168.1.102/24`.

From your workstation, scan for Pantavisor devices on the local network:

```bash
pvr device scan
```

## SSH Access

SSH is served by the pvr-sdk container running on the device. The default credentials for starter images are:

- **Username**: `root`
- **Password**: `pantavisor`

```bash
ssh root@<device-ip>
```

Once connected you have a shell inside the pvr-sdk container. From there you can reach the Pantavisor host commands via `pvcontrol`, check container state with `lxc-ls -f`, or enter other containers with `pventer`.

## pvr CLI Access

With the device's IP, your workstation can clone and manage the device state directly:

```bash
pvr clone http://<device-ip>:12368/cgi-bin/pvr my-device
```

Pantavisor exposes the revision management endpoint on port **12368**. All `pvr` operations — adding containers, deploying revisions — communicate through this port.

## pvtx Web UI

Open a browser to:

```
http://<device-ip>:12368/app
```

The pvtx UI shows the current revision state, running containers, logs, and device configuration. You can also upload container packages and commit transitions from here.

## Security

The default `pantavisor` password should be changed before production use. Add your SSH public key to avoid password-based login:

```bash
# Inside the pvr-sdk container (via SSH or pventer)
mkdir -p ~/.ssh
cat >> ~/.ssh/authorized_keys <<'EOF'
<paste your public key here>
EOF
chmod 600 ~/.ssh/authorized_keys
```

To make the change persistent across updates, add the key through the `_config/pvr-sdk/` overlay in your `pvr` checkout (see [Configure Applications](../../application/configure/)).