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

In Pantavisor, all user-space software and services are managed as containerized **Applications**. By isolating applications within their own containers (such as LXC or Docker-compatible environments), Pantavisor ensures that services run securely, manage their own dependencies, and can be updated independently of the core host system.

This section covers the complete lifecycle of managing applications on your Pantavisor device. You will learn how to:

*   **[Install Applications](./install/)**: Discover the different methods for deploying new containerized services to your device, whether locally using `pvr` or `pvtx`, or remotely via Pantahub.
*   **[Configure Applications](./configure/)**: Customize application behavior by modifying their `run.json` manifests, mounting storage volumes, setting up networking, and managing environment variables.
*   **[Access Applications](./access-applications/)**: Learn how to interact with running applications, expose container ports to the host network, and communicate between services.
*   **[View Applications](./view/)**: Monitor the status of your deployed applications, inspect container health, and stream application logs.
*   **[Remove Applications](./remove/)**: Clean up your device state by securely stopping and removing applications you no longer need.

By understanding how to manage applications, you unlock the true potential of Pantavisor as a flexible, modular platform for embedded edge devices.
