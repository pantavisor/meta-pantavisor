---
title: Applications
sidebar_position: 20
description: Comprehensive guide on managing applications within Pantavisor Linux. Learn how to install, configure, access, view, and remove containerized services on your device.
---

In Pantavisor, every piece of user space — applications, system services, even OS components — runs as an isolated **LXC container**. Each container has its own read-only root filesystem (a SquashFS image), its own LXC configuration, and a `run.json` manifest that controls restart policy, auto-recovery, and service-mesh wiring.

Containers are versioned as part of the device's **revision trail** (the `trails/` directory on storage). Any change — adding an app, updating a config file, removing a service — produces a new revision that Pantavisor applies atomically. If anything goes wrong, it rolls back to the previous good revision automatically.

This section covers the complete lifecycle of managing applications on a Pantavisor device:

*   **[Install Applications](./install/)**: Add containerized services to your device using the `pvr` CLI directly, through the pvtx local web UI, or remotely via Pantahub.
*   **[Configure Applications](./configure/)**: Customize container behaviour by editing the `_config/<container>/` overlay tree in your local `pvr` repository, then deploying the new revision.
*   **[View Applications](./view/)**: Monitor running containers, inspect health and auto-recovery state, and stream logs — on-device with `pvcontrol` and `lxc-ls`, or through the pvtx web UI.
*   **[Access Applications](./access-applications/)**: Enter a running container's namespace with `pventer`, reach its network ports, or wire services together with the pv-xconnect service mesh.
*   **[Remove Applications](./remove/)**: Remove a container from the device state with `pvr app rm`, commit, and deploy — Pantavisor stops and discards the container on the next revision.
