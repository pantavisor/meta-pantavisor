---
title: "What is Pantavisor?"
description: "Understanding Pantavisor's role in the embedded Linux ecosystem"
lead: "Pantavisor is a lightweight container framework that brings modern DevOps practices to embedded Linux development."
date: 2025-09-14T00:00:00+00:00
lastmod: 2025-09-14T00:00:00+00:00
draft: false
images: []
weight: 111
toc: true

# SEO Configuration
keywords: ["what is pantavisor", "pantavisor explained", "embedded container framework", "lightweight linux containers", "embedded devops", "iot container orchestration", "modular embedded updates", "embedded linux containerization", "pantavisor vs docker", "embedded system architecture"]
meta_description: "What is Pantavisor? A lightweight container framework for embedded Linux that enables modular updates, DevOps workflows, and secure IoT device management."
author: "Pantacor Ltd"

# Open Graph / Social Media
og_title: "What is Pantavisor? - Embedded Linux Container Framework"
og_description: "Discover Pantavisor: The lightweight container framework transforming embedded Linux development with modular updates and DevOps practices."
og_type: "article"
og_image: "/images/logo-pantacor.png"

# Twitter specific
twitter_title: "What is Pantavisor? - Embedded Container Framework"
twitter_description: "Learn about the lightweight container framework revolutionizing embedded Linux development"
twitter_card: "summary_large_image"

# SEO Settings
robots: "index, follow"
sitemap_priority: 0.9
sitemap_changefreq: "monthly"
canonical_url: "https://www.pantavisor.io/learn/concepts/what-is-pantavisor/"
---

## What Pantavisor Is

**Pantavisor** is an open-source, container-based embedded Linux system runtime. It boots from a minimal initramfs — there is no conventional root filesystem — and manages the entire device lifecycle: starting LXC containers in dependency order, delivering OTA updates atomically, and exposing a local REST API for control. Every piece of user space (applications, OS services, BSP components like kernel modules and firmware) lives in its own LXC container. The host initramfs contains only Pantavisor itself.

## The Problem It Solves

Traditional embedded Linux development is built around monolithic images: a single firmware artifact contains the kernel, BSP drivers, OS, and all applications. Every change — even a one-line config fix — means rebuilding the whole image, re-flashing the device, and risking a brick if anything goes wrong mid-update. Teams working on the BSP, the OS, and the application layer step on each other because their work ships as one indivisible unit.

Pantavisor breaks that monolith apart:

- Each component is an independent LXC container that can be built, tested, and updated in isolation
- OTA updates target only the changed containers, not the full image
- Failed updates roll back automatically to the last known-good revision
- Container isolation means a crashed application cannot destabilize the BSP or OS layers

## Architecture

```
┌───────────────────────────────────────────────┐
│  Applications (LXC containers)                │ ← your app, Home Assistant, etc.
├───────────────────────────────────────────────┤
│  System services (LXC containers)             │ ← networking, daemons, middleware
├───────────────────────────────────────────────┤
│  BSP (LXC container)                          │ ← kernel modules, firmware squashfs
├───────────────────────────────────────────────┤
│  Pantavisor runtime  (~1 MB)                  │ ← container orchestrator + OTA agent
├───────────────────────────────────────────────┤
│  Minimal initramfs                            │ ← contains only Pantavisor itself
├───────────────────────────────────────────────┤
│  Linux kernel                                 │
├───────────────────────────────────────────────┤
│  Board Support Package (bootloader, DTBs)     │
└───────────────────────────────────────────────┘
```

Pantavisor sits between the kernel and all user space. It replaces the init system and owns everything above it.

## Device State Model

A Pantavisor device maintains a versioned trail of *revisions* in `/trails/`. Each revision is a complete snapshot of the running system:

```
/trails/
└── 0/              ← current revision
    ├── bsp/        ← kernel image, modules.squashfs, firmware.squashfs, DTBs
    ├── network/    ← network container rootfs and metadata
    ├── app/        ← application container rootfs and metadata
    ├── device.json ← device-level configuration (groups, auto-recovery policy)
    └── #spec       ← format version marker used by pvr
```

When an OTA update arrives, Pantavisor writes the incoming objects to a *pending* revision, reboots into it, and — if the new revision reports healthy — promotes it to current. If not, it rolls back to the previous revision automatically, without operator intervention.

## Key Components

### Pantavisor Runtime

The core daemon runs in the initramfs and is responsible for:

- Mounting the storage partition and reading device state from `/trails/`
- Starting and supervising LXC containers in declared dependency order
- Polling [Pantahub](https://pantahub.com) for OTA updates and delivering logs
- Exposing the local control socket (`pvcontrol`)

### pvr — Device State CLI

`pvr` is the developer-facing tool for Pantavisor state. It is modelled on Git: you `clone` a device, `add` containers (from Docker Hub images or local pvrexport bundles), `commit` changes, and `push` to Pantahub to deliver an OTA update. The pvr workflow works from a developer workstation and integrates naturally into CI/CD pipelines.

```bash
pvr clone http://192.168.1.122:12368/cgi-bin/pvr my-device
cd my-device
pvr app add --from nginx:stable-alpine webserver
pvr add . && pvr commit -m "add nginx"
pvr deploy trails/0 .
```

### pvcontrol — Local REST API

The `pvcontrol` socket exposes a REST API for querying and controlling the running device state without cloud connectivity:

```bash
pvcontrol daemons ls    # list running containers
pvcontrol graph ls      # inspect the xconnect service mesh
pvcontrol ls            # full device status including auto-recovery counters
```

### pv-xconnect — Container Service Mesh

`pv-xconnect` mediates communication between containers without requiring a shared network namespace. It injects sockets, device nodes, and service endpoints directly into each container's namespace:

| Type | What it connects |
|------|-----------------|
| `unix` | Raw Unix domain socket proxy |
| `rest` | HTTP-over-UDS with caller-identity headers (`X-PV-Client`, `X-PV-Role`) |
| `dbus` | Policy-aware D-Bus proxy with interface filtering |
| `drm` | DRM device node injection (`card0`, `renderD128`) |
| `wayland` | Wayland compositor access for isolated UI containers |

### Pantahub — Cloud Backend

[Pantahub](https://pantahub.com) is the cloud service that devices register with. It stores device state, delivers OTA updates as object diffs, and aggregates logs. The `pvr` CLI authenticates to Pantahub so developers can manage a fleet of devices remotely from their workstation.

## OTA Updates

Updates are delivered as diffs, not full images. Only the objects (container rootfs, modules squashfs, config files) that changed are transferred. The update flow is:

1. Developer commits and pushes new state with `pvr`
2. Device polls Pantahub and downloads the diff
3. Pantavisor writes the new objects to a pending revision
4. Device reboots into the pending revision
5. If the revision boots cleanly and all containers reach their health goal, it is committed as the new current state
6. If any step fails, Pantavisor restores the previous revision and reboots

## Auto-Recovery

Each container (or container group) can declare a recovery policy in `device.json` or `run.json`:

| Policy | Behaviour |
|--------|-----------|
| `on-failure` | Restart on non-zero exit only |
| `always` | Restart on any exit |
| Exponential backoff | Configurable `retry_delay` and `backoff_factor` |
| `backoff_policy: "reboot"` | Reboot device after max retries |
| `backoff_policy: "10min"` | Wait 10 minutes, then reset retry counter and try again |
| `backoff_policy: "never"` | Leave container stopped; do not reboot |

Containers with a `stable_timeout` hold the OTA commit until they have run cleanly for the configured window, preventing a bad update from being permanently committed.

## Security Features

| Feature | Description |
|---------|-------------|
| dm-crypt | Full storage encryption for the trails partition |
| dm-verity | Per-container rootfs integrity verification at mount time |
| Signed state | PVR state signing with X.509 keys (`pvr sig`) |
| Secure boot | U-Boot verified boot / FIT image signing (platform-dependent) |

## Comparison with Traditional Embedded Linux

| Aspect | Traditional | Pantavisor |
|--------|-------------|------------|
| **Update unit** | Full image (100–500 MB) | Changed containers only (1–50 MB) |
| **Update time** | 5–30 minutes | 30 seconds – 5 minutes |
| **Rollback** | Complete reflash | Automatic on next boot |
| **Component isolation** | Monolithic process tree | Separate LXC namespace per container |
| **Failed-update recovery** | Manual intervention | Automatic rollback to previous revision |
| **Build model** | Single monolithic build | Independent container builds |

## Real-World Example

A connected sensor device running Pantavisor:

```
/trails/0/
├── bsp/
│   ├── kernel.img
│   ├── modules_6.1.77.squashfs   ← kernel modules
│   └── firmware.squashfs         ← WiFi/BT firmware blobs
├── network/                      ← NetworkManager container (~8 MB)
├── sensor-app/                   ← sensor logic container (~12 MB)
└── web-ui/                       ← dashboard container (~15 MB)
```

Updating the dashboard means transferring only the changed `web-ui` objects. The BSP, network stack, and sensor app keep running through the update — no full reflash, no downtime for unrelated components.

## Next Steps

- **Get Started**: Follow the [Quick Start Guide](../device-setup/) to flash your first Pantavisor image.
- **pvr CLI**: See the [pvr CLI reference](../../cli-tools/pvr-cli/) for the full command set.
- **Deep Dive**: The [Pantahub documentation](https://docs.pantahub.com/) covers the API, container authoring, and BSP integration in detail.