+++
title = "Device Access"
weight = 10

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

### Accessing a Pantavisor-enabled Device

You have several flexible options for accessing and interacting with a device running Pantavisor. These methods allow you to choose the best way to connect, whether for initial setup or ongoing interaction.

### Initial Access

For initial device access, a **serial port** provides the most direct and reliable connection. This low-level method allows you to see boot messages, troubleshoot issues, and perform initial configuration, such as setting up network connectivity.

Once the device is configured, you can connect via a local network using **Ethernet** or **Wi-Fi**. This enables more convenient access, such as through **SSH**, for local management from your computer.

### Ongoing Management and Access

For ongoing device access and management, Pantavisor provides two primary paths:

* **Local Experience:** You can directly manage your devices from your host computer using tools like **pvtx**, which provides a web UI stored on the device itself, and the **PVR CLI** for command-line management.
* **Remote Experience:** For remote access and management, you can use **Pantacor Hub**. This platform allows you to manage your devices and their software from a cloud-based interface.

Note that you can easily switch between local and remote access modes on the fly, giving you the flexibility to use the method that best suits your needs at any given moment.