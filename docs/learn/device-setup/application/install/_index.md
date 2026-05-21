+++
title = "Install apps"
weight = 20

# SEO Configuration
description = "Quick start guide for setting up Pantavisor Linux on your device. Flash images, configure network, install applications in just a few minutes."
keywords = ["pantavisor quick start", "pantavisor setup", "embedded linux setup", "iot device setup", "raspberry pi pantavisor", "flash pantavisor", "embedded container setup", "pantavisor installation", "iot linux installation"]
meta_description = "Quick Start: Set up Pantavisor Linux on your device in 5 minutes. Complete guide from flashing to installing your first containerized application."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Pantavisor Quick Start - Device Setup Guide"
og_description = "Get Pantavisor Linux running on your device in 5 minutes. Complete setup guide from flashing to first application installation."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Pantavisor Quick Start - 5 Minute Setup"
twitter_description = "Set up containerized embedded Linux on your device in just 5 minutes"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.9
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/"
+++

Every application on a Pantavisor device is an LXC container added to the device's revision trail. There are three ways to install a new container, depending on whether you want a command-line-only workflow, a local web upload, or cloud-based remote management.

---

### 1. pvr CLI over the Local Network

The `pvr` CLI is the primary tool for managing device state. You clone the device, add a container from a Docker Hub image or a pvrexport bundle, commit, and deploy — all from your workstation over the local network. This is the recommended method for development and automation.

→ [Install with pvr CLI](./local-pvr/)

### 2. pvtx Web UI over the Local Network

The pvtx interface is served directly from the device on port 12368. You build a container package on your workstation using `pvr`, export it as a `.tar.gz` archive, then upload it through the browser UI and commit the transaction from there. Useful for one-off installs without setting up a full pvr workflow.

→ [Install via pvtx](./local-pvtx/)

### 3. Remotely via Pantahub

If the device is registered with [Pantahub](https://pantahub.com), you can push updates from anywhere. Claim the device in your Pantahub account, upload the container package through the Pantahub dashboard, and commit the transaction. The device pulls the new revision from the cloud and applies it automatically.

→ [Install via Pantahub](./remote-pantahub/)