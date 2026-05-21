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

Find answers to commonly asked questions about the Pantavisor Linux container framework.

## App Management

### How do I delete apps from my device?

To uninstall an app, use the PVR CLI in edit mode:

1. **Start an edit session**

   ```bash
   pvr checkout
   ```

2. **Remove the app files and its config overlays**

   ```bash
   rm -rf container_folder
   rm -rf _config/container_folder
   ```

3. **Commit and apply the changes**

   ```bash
   pvr add .
   pvr commit
   pvr post -a
   ```

### How do I edit application configurations?

Pantavisor provides configuration editing through the PVR CLI:

- **Edit mode** — Start a session with `pvr checkout`, make your changes, and commit with `pvr commit`
- **Container metadata** — Modify container `.json` files within the checked-out state
- **Configuration overlays** — Manage overlay configurations in the `_config` directory outside containers

After editing, commit and post the new revision so the device picks up the changes on the next reboot.

## Connectivity Issues

### My device is not connecting. How do I fix it?

Common connectivity troubleshooting steps:

1. **Check network connection**
   - Verify ethernet cable connection
   - Ensure WiFi credentials are correct
   - Test network connectivity from another device

2. **Verify device boot**
   - Check that the device boots properly
   - Look for the Pantavisor Linux logo
   - Confirm login prompt appears

3. **Network configuration**
   - Use `pvr device scan` to discover device IP
   - Check router DHCP assignments
   - Try connecting via ethernet if WiFi fails

## Technical Questions

### How are Docker containers handled by Pantavisor Linux?

Pantavisor doesn't run Docker containers natively. Instead:

- Docker images serve as root file systems
- Containers run using LXC (Linux Containers)
- Images are converted automatically during installation
- Configuration overlays provide customization outside the container

### What is the `_config` directory?

The `_config` directory contains overlay configurations that:

- Override container-internal configurations
- Provide persistent customization across updates
- Map directly to paths inside containers
- Take precedence over internal container configs

### What is the pvr command line interface?

PVR (Pantavisor Revision) is a git-like CLI tool for:

- Managing device states and revisions
- Committing configuration changes
- Scanning and discovering devices
- Synchronizing with remote repositories
- Handling rollbacks and state management

For detailed PVR documentation, see the [Official PVR Reference Guide](https://docs.pantahub.com/pvr/).

## Getting Help

Having issues not covered here? Join our community forum at [Pantavisor Community Forum](https://community.pantavisor.io) for additional support and discussion.