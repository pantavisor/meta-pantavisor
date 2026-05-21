+++
title = "Applications"
weight = 20

# SEO Configuration
description = "Comprehensive guide on managing applications within Pantavisor Linux. Learn how to install, configure, access, view, and remove containerized services on your device."
keywords = ["pantavisor applications", "containerized services", "embedded linux apps", "iot applications", "pantavisor install", "pantavisor configure", "manage containers"]
meta_description = "Manage Applications: Complete guide to the lifecycle of containerized applications in Pantavisor Linux, from installation to removal."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Manage Applications in Pantavisor"
og_description = "Learn how to deploy, configure, and manage containerized applications on your Pantavisor device."
og_type = "article"
og_image = "/images/logo-pantacor.png"

# Twitter specific
twitter_title = "Manage Pantavisor Applications"
twitter_description = "A guide to the lifecycle of containerized apps in Pantavisor"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.8
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/application/"
+++

In Pantavisor, every piece of user space — applications, system services, even OS components — runs as an isolated **LXC container**. Each container has its own read-only root filesystem (a SquashFS image), its own LXC configuration, and an optional `run.json` manifest that controls restart policy, auto-recovery, and service-mesh wiring.

Containers are versioned as part of the device's **revision trail** (`/trails/`). Any change — adding an app, updating a config file, removing a service — produces a new revision that Pantavisor applies atomically. If anything goes wrong, it rolls back to the previous good revision automatically.

This section covers the complete lifecycle of managing applications on a Pantavisor device:

*   **[Install Applications](./install/)**: Add containerized services to your device using the `pvr` CLI directly, through the pvtx local web UI, or remotely via Pantahub.
*   **[Configure Applications](./configure/)**: Customize container behaviour by editing the `_config/<container>/` overlay tree in your local `pvr` repository, then deploying the new revision.
*   **[View Applications](./view/)**: Monitor running containers, inspect health and auto-recovery state, and stream logs — on-device with `pvcontrol` and `lxc-ls`, or through the pvtx web UI.
*   **[Access Applications](./access-applications/)**: Enter a running container's namespace with `pventer`, reach its network ports, or wire services together with the pv-xconnect service mesh.
*   **[Remove Applications](./remove/)**: Remove a container from the device state with `pvr app rm`, commit, and deploy — Pantavisor stops and discards the container on the next revision.
