---
title: "Frequently Asked Questions"
weight: 10

# SEO Configuration
description: "Frequently asked questions about Pantavisor Linux. Get answers to common questions about app management, connectivity, and technical issues."
keywords: ["pantavisor faq", "frequently asked questions", "pantavisor help", "common questions", "pantavisor answers", "embedded linux faq", "docker containers pantavisor", "pvr cli", "pantavisor support", "troubleshooting faq"]
meta_description: "Pantavisor FAQ: Find answers to frequently asked questions about app management, connectivity issues, Docker containers, and PVR CLI usage."
author: "Pantacor Ltd"

# Open Graph / Social Media
og_title: "Pantavisor Linux Frequently Asked Questions"
og_description: "Get answers to common questions about Pantavisor Linux including app management, connectivity, and technical troubleshooting."
og_type: "article"
og_image: "/images/logo-pantacor.png"

# Twitter specific
twitter_title: "Pantavisor Linux FAQ"
twitter_description: "Common questions and answers about Pantavisor containerized embedded Linux"
twitter_card: "summary_large_image"

# SEO Settings
robots: "index, follow"
sitemap_priority: 0.7
sitemap_changefreq: "monthly"
canonical_url: "https://www.pantavisor.io/learn/troubleshooting/faq/"
---

## App Management

### How do I remove an app from my device?

Clone the device, remove the container with `pvr app rm`, commit, and deploy:

```bash
pvr clone http://<device-ip>:12368/cgi-bin/pvr my-device
cd my-device
pvr app rm my-old-app
pvr add .
pvr commit -m "remove my-old-app"
pvr deploy trails/0 .
```

Pantavisor stops the container and removes it from the trail on the next boot.

### How do I edit an application's configuration?

Container rootfs images (`root.squashfs`) are read-only. To overlay files on top of them, add files to `_config/<container-name>/` in your pvr checkout. The directory structure mirrors where those files live inside the container.

```bash
pvr clone http://<device-ip>:12368/cgi-bin/pvr my-device
cd my-device
mkdir -p _config/my-app/etc/myapp
# edit _config/my-app/etc/myapp/config.json
pvr add .
pvr commit -m "update my-app config"
pvr deploy trails/0 .
```

To change Pantavisor-level behaviour (restart policy, auto-recovery, environment variables), edit the container's `run.json` directly in the checkout directory. See [Configure Applications](../../device-setup/application/configure/).

### How do I update a container to a newer image version?

```bash
pvr app update my-app --from myorg/myapp:v2.0.0
pvr add .
pvr commit -m "update my-app to v2.0.0"
pvr deploy trails/0 .
```

### What happens if an OTA update fails?

Pantavisor automatically rolls back to the previous revision if the new one fails to boot or any container does not reach its health goal within the configured timeout. No manual intervention is needed. The previous revision is kept in `/trails/` and restored on the next boot.

---

## Connectivity Issues

### My device is not showing up on the network.

1. Check the Ethernet cable or Wi-Fi credentials.
2. From the serial console, verify the device has an IP: `ip addr show eth0`
3. Scan from your workstation: `pvr device scan`
4. Check the Pantavisor log for DHCP or network container errors:
   ```bash
   tail /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log
   ```

### pvr clone fails with "connection refused".

Pantavisor serves the state API on port **12368**. Confirm:

- The device has a network address: `ip addr show`
- The pvr-sdk (or network) container is running: `lxc-ls -f`
- You are using the full URL: `pvr clone http://<device-ip>:12368/cgi-bin/pvr <dir>`

---

## Technical Questions

### How does Pantavisor run Docker images?

Pantavisor does not use the Docker runtime. `pvr app add --from <image>` pulls a Docker Hub image and converts it into an LXC container:

1. The image layers are merged into a single SquashFS rootfs (`root.squashfs`)
2. An `lxc.container.conf` is generated with appropriate mount and namespace settings
3. An optional `run.json` is created for Pantavisor-level metadata

The container runs under LXC, not Docker. There is no Docker daemon on the device.

### What is the `_config/` directory?

`_config/<container-name>/` in a pvr checkout is a writable file overlay. Files placed there are layered on top of the container's read-only `root.squashfs` at runtime — analogous to a bind-mount overlay. The path inside `_config/<container-name>/` mirrors the path inside the container.

This lets you add SSH keys, config files, or scripts to a container without rebuilding its SquashFS image.

### What is `pvr`?

`pvr` (Pantavisor Revision) is a Git-like CLI for managing device state. Core operations:

| Command | What it does |
|---------|-------------|
| `pvr clone <url> <dir>` | Clone a device's current revision to a local directory |
| `pvr app add --from <image>` | Convert a Docker image to a Pantavisor container |
| `pvr app rm <name>` | Remove a container from the local state |
| `pvr add .` | Stage all changes |
| `pvr commit -m "..."` | Record a new local revision |
| `pvr deploy trails/0 .` | Push the revision to the device |
| `pvr device scan` | Discover Pantavisor devices on the local network |
| `pvr sig add --part <name>` | Sign a container with an X.509 key |

Full reference: [pvr CLI](../../cli-tools/pvr-cli/).

### Why are `xconnect`, `pvcontrol`, or `rngdaemon` missing from my image?

This is almost always caused by using `+=` instead of `:append` when setting `PANTAVISOR_FEATURES` in a distro include file. The `??=` weak default in `pvbase.bbclass` is silently overwritten by `+=`:

```bitbake
# WRONG — drops all defaults including xconnect, pvcontrol, rngdaemon
PANTAVISOR_FEATURES += "appengine"

# CORRECT — preserves defaults and appends
PANTAVISOR_FEATURES:append = " appengine"
```

---

## Getting Help

- [Pantavisor Community Forum](https://community.pantavisor.io)
- [Official pvr Reference](https://docs.pantahub.com/pvr/)
- [Pantahub Documentation](https://docs.pantahub.com/)