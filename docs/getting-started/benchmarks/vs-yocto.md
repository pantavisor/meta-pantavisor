---
title: Pantavisor vs Yocto
sidebar_position: 1
description: Pantavisor doesn't replace Yocto — it complements it. Use Yocto to build the BSP, then add Pantavisor for container composability, atomic OTA, and fleet management.
---

# Pantavisor vs Yocto — complementary, not competitive

## The short answer: use both

**Pantavisor is not a Yocto alternative — it's a Yocto companion.**

If you're already using Yocto to build embedded Linux images, you don't need to
replace it. Pantavisor provides a Yocto layer
([`meta-pantavisor`](/meta-pantavisor/overview/get-started)) that adds container orchestration, atomic OTA
updates, and fleet management to your existing Yocto-built firmware.

## What each tool does best

| Task | Yocto | Pantavisor |
|---|---|---|
| Build kernel & drivers | ✅ Best-in-class | — |
| Create BSP for new hardware | ✅ Best-in-class | — |
| Generate toolchain | ✅ Best-in-class | — |
| Base rootfs creation | ✅ Best-in-class | — |
| Container orchestration | ❌ Not designed for | ✅ Purpose-built |
| Atomic OTA updates | ⚠️ Bolt-on (Mender, SWUpdate, RAUC) | ✅ Built-in |
| Fleet management | ❌ Not included | ✅ Pantahub (open source) |
| Signed system state | ⚠️ Image signing only | ✅ PVS over state JSON |
| Independent app updates | ⚠️ No built-in mechanism (package feeds possible) | ✅ Update a single container |
| Kernel as a container | ❌ No | ✅ Yes (BSP container) |

## The problem with Yocto alone

Yocto is excellent at building firmware, but on its own it has limitations:

1. **Monolithic updates** — every change requires rebuilding and reflashing the entire image.
2. **Slow iteration** — full cold builds take 30–60 minutes; sstate-cache brings
   incremental rebuilds down to minutes, but every app change still means a
   rebuild-and-reflash cycle.
3. **Risky deployments** — no automatic rollback if an update fails.
4. **No fleet visibility** — managing thousands of devices requires external tools.

## The solution: Yocto + Pantavisor

Two phases, two tools, one workflow:

**Yocto phase** — build once, rarely changes:

- Build the kernel + device tree for your board.
- Build the BSP container (kernel, modules, firmware).
- Compose the initial container set.
- Output: a full bootable `.wic` image with Pantavisor as PID 1.

**Pantavisor phase** — iterate fast, deploy often:

- Clone the device state with `pvr clone`.
- Compose / update / remove containers (`pvr app add|update|rm`).
- Sign, stage, and push (`pvr sig add`, `pvr add .`, `pvr commit`, `pvr post`).
- Pantavisor switches atomically and rolls back if any container fails its `status_goal`.

## How it works in practice

### 1. Build a Pantavisor-enabled image with Yocto

The fastest path is the KAS-driven build that ships in `meta-pantavisor`:

```bash
git clone https://github.com/pantavisor/meta-pantavisor.git
cd meta-pantavisor

# Builds BSP + Pantavisor + initial container composition into a flashable .wic
./kas-container build kas/build-configs/release/raspberrypi-armv8-scarthgap.yaml
```

See [Build with Yocto](/meta-pantavisor/overview/get-started) for the full guide.

### 2. Flash and boot

```bash
# from the build's deploy/images/raspberrypi-armv8/ directory
pvflasher copy pantavisor-starter-raspberrypi-armv8*.wic.bz2 /dev/sdX
```

On first boot the device can register with Pantahub and get a nickname.

### 3. Manage everything above the kernel with pvr

```bash
# Clone the device state
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME my-device
cd my-device

# Add / update / remove containers
pvr app add wificonnect --from gitlab.com/pantacor/pvwificonnect:latest

# Sign, stage, commit, push
pvr sig add --part wificonnect
pvr add .
pvr commit -m "Add wificonnect"
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

## With vs without Pantavisor

| Scenario | Yocto + typical image updater | Yocto + Pantavisor |
|---|---|---|
| Update a Python app | Rebuild image (30–60 min cold, minutes with sstate-cache) | Update container (2–5 min) |
| Deploy to 10,000 devices | Full-image OTA to all devices | `pvr post` only the changed objects |
| Update fails | Recovery depends on the updater's rollback integration | Automatic, health-gated rollback |
| Add a new service | Rebuild image | `pvr app add` |
| Team A updates kernel | Affects Team B's apps | Isolated container updates |

## When to choose Yocto alone

- Your firmware is truly static (no app updates ever).
- You're building a single prototype.
- Your team has no container expertise.
- The hardware has very little storage.

## When to add Pantavisor

- **Faster iteration** — update apps without rebuilding the entire BSP.
- **OTA updates** — deploy to devices in the field.
- **Fleet management** — manage many devices from one place.
- **App composability** — mix and match apps per product variant.
- **Team independence** — kernel team and app team work independently.

## Key takeaway

> **Yocto builds the ship. Pantavisor loads the cargo and charts the course.**

Use Yocto for what it's great at — building the BSP. Use Pantavisor for what it's
great at — managing the dynamic parts of your system.

## Next steps

- [Build with Yocto](/meta-pantavisor/overview/get-started) — the meta-pantavisor build guide
- [Develop applications](/meta-pantavisor/getting-started/develop) — manage containers after the build
- [meta-pantavisor on GitHub](https://github.com/pantavisor/meta-pantavisor)
