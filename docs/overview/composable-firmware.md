---
title: Composable firmware — the end-to-end workflow
sidebar_position: 16
description: The two-phase Pantavisor workflow — build the initial image with Yocto, then maintain the running device with pvr and Pantahub. The golden path from image to OTA, with canonical commands.
---

# Composable firmware — the end-to-end workflow

**Composable firmware** means every layer of the device — kernel/BSP, system
services, and applications — is an independent container, and the whole device is
one signed, content-addressed [revision](/pantavisor/overview/revisions). You build
the device once, then update any piece of it over the air without reflashing the
rest.

This page is the **map** of the full workflow. Each step gives the one canonical
command and links to the deep guide.

## The two-phase model (read this first)

Pantavisor's lifecycle has exactly two phases, owned by two different tools:

| Phase | Tool | Input | Output | Use it to | It cannot |
|---|---|---|---|---|---|
| **Build** | Yocto + [`meta-pantavisor`](/meta-pantavisor/overview/get-started) (`kas`/`bitbake`) | recipes + container sources | a flashable `.wic` / `.pvrexport.tgz` | produce the **initial** image | push an OTA update |
| **Maintain** | [`pvr`](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli) + Pantahub | a cloned device state | a new signed **revision** | update a **running** device | build a flashable image |

> **⚠️ Don't mix the phases**
>
> `pvr` cannot produce a flashable image, and Yocto cannot push an OTA update to a
> running device. Build the first image with Yocto; change everything afterward
> with `pvr`. If you find yourself "rebuilding the image to update an app," you're
> in the wrong phase — clone the device and `pvr post` instead.

## The device, once it's running

A booted Pantavisor device is one revision made of containers:

```
/trails/0/                 ← the current revision (one signed state)
├── bsp/                   ← kernel + modules + firmware (a container)
├── os/                    ← base userland / networking (a container)
└── <your-app>/            ← your application (a container)
```

Updating any one of these — even the kernel — is the same operation: produce a
new revision and post it. See [What is Pantavisor?](/pantavisor/overview)
for the architecture in depth.

## The golden path

### 1. Get a Pantavisor image  ·  *build phase*

Download a pre-built starter image for a supported board, **or** build one with
Yocto for custom hardware:

```bash
git clone https://github.com/pantavisor/meta-pantavisor.git
cd meta-pantavisor
./kas-container build kas/build-configs/release/raspberrypi-armv8-scarthgap.yaml
```

→ [Build with Yocto](/meta-pantavisor/overview/get-started) · [Get started with meta-pantavisor](/meta-pantavisor/overview/get-started)

### 2. Flash it

```bash
sudo pvflasher copy pantavisor-starter-<machine>*.wic.bz2 /dev/sdX
```

→ [Download and flash](/meta-pantavisor/getting-started/start/download-and-flash) · [Install on hardware](/meta-pantavisor/getting-started/how-to-install)

### 3. Boot, access, and (optionally) claim

On first boot the device brings up every baked-in container. Reach it over the
serial console or the local network, and — if you want remote OTA — claim it on
Pantahub:

```bash
cat /pv/device-id        # on the device console
cat /pv/challenge        # enter both at hub.pantacor.com → Claim Device
```

→ [Device access](/meta-pantavisor/getting-started/operate/device-access) · [Claim via Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub)

### 4. Compose and change containers  ·  *maintain phase*

Clone the running device's state, add/update/remove containers, and commit:

```bash
pvr clone http://<device-ip>:12368/cgi-bin my-device
cd my-device
pvr app add myapp --from myorg/myapp:latest --platform linux/arm64
pvr add . && pvr commit -m "add myapp"
```

→ [Develop applications](/meta-pantavisor/getting-started/develop) · [Install apps](/meta-pantavisor/getting-started/develop/application/install)

### 5. Ship the update (OTA)

Post the new revision to the device. Pantavisor switches atomically and rolls
back automatically if any container fails its health goal:

```bash
# Local network (the same endpoint you cloned from)
pvr post http://<device-ip>:12368

# Or remotely via Pantahub
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

→ [Operate devices](/meta-pantavisor/getting-started/operate) · [Atomicity and trust](/meta-pantavisor/getting-started/security/atomicity-and-trust)

## Canonical commands (quick reference)

```bash
# Build phase (Yocto) — produces the initial flashable image
./kas-container build kas/build-configs/release/<machine>-scarthgap.yaml

# Maintain phase (pvr) — updates a running device
pvr clone http://<device-ip>:12368/cgi-bin my-device   # local clone (note: /cgi-bin)
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME my-device   # remote clone
pvr app add <name> --from <image> --platform <arch>    # add a container from a Docker/OCI image
pvr app update <name> --from <image>                   # update a container
pvr app rm <name>                                      # remove a container
pvr add . && pvr commit -m "<message>"                 # stage + record a revision
pvr post http://<device-ip>:12368                      # push to a local device (no /cgi-bin)
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME # push via Pantahub
```

For the full command set see the [`pvr` CLI reference](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli),
the [on-disk layout](/meta-pantavisor/getting-started/develop/cli-tools/configuration), and the
[state format schema](/pantavisor/reference/pantavisor-state-format-v2).
