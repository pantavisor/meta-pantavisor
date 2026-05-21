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

### Methods for Adding a New Container to Pantavisor

When you need to add a new application container to your Pantavisor-enabled system, you have several flexible options depending on your setup and workflow.

---

#### 1. Via the Local Network with the pvr CLI

For a more streamlined, command-line-only experience, you can add and post new containers directly to the device over the local network using only the **pvr CLI**. This approach bypasses the web UI and is a powerful way to integrate your Pantavisor workflow into scripts or automated processes.

#### 2. Via the Local Network and Web UI (pvtx)

This method is ideal for quick, local updates. It involves using the **pvr CLI** on your development machine to prepare the container and then uploading it directly to the device through its local web interface, **pvtx**. This is great for testing and development in a contained environment.

#### 3. Via a Remote Connection from PantaHub

If your device is connected to **PantaHub**, you can manage it remotely. This allows you to prepare a new container on your development machine and then push the update to the device through PantaHub. The device will then pull the new revision from the cloud, making this method perfect for managing a fleet of devices from anywhere in the world.