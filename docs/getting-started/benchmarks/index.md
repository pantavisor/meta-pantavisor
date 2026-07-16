---
title: Benchmarks and comparisons
description: How Pantavisor compares to Yocto, Balena, Buildroot, Docker, and image updaters — capability matrix plus reproducible payload/time/flash numbers.
sidebar_position: 9
---

# Benchmarks and comparisons

Choosing an embedded Linux approach is a long-lived decision. This section
compares Pantavisor to the common alternatives on capability, and will back the
efficiency claims with reproducible numbers (methodology below).

## Pantavisor vs alternatives

Pantavisor offers **composable firmware through lightweight LXC containers** —
including the kernel/BSP as a container — which differs from both traditional
build systems and container platforms.

| Feature | Pantavisor | Yocto | Balena | Buildroot | Docker |
|---|---|---|---|---|---|
| Composable architecture | ✅ Full stack | ❌ Monolithic | ⚠️ App-only | ❌ Monolithic | ⚠️ App-only |
| Container runtime | ✅ LXC (~1 MB) | ⚠️ Not built-in (meta-virtualization exists) | ✅ Docker | ❌ None | ✅ Docker |
| Kernel as a container | ✅ Yes | ❌ No | ❌ No | ❌ No | ❌ No |
| Atomic OTA rollback | ✅ Built-in | ⚠️ Bolt-on | ✅ Yes | ⚠️ Manual | ⚠️ Partial |
| Resource constrained | ✅ ~1 MB core | N/A (build system) | ⚠️ Heavy | N/A (build system) | ⚠️ Heavy |
| Bare-metal performance | ✅ Yes | ✅ Yes | ⚠️ Overhead | ✅ Yes | ⚠️ Overhead |
| Offline operation | ✅ Full | ✅ Yes | ⚠️ Limited | ✅ Yes | ⚠️ Limited |
| Open source | ✅ 100% | ✅ Yes | ⚠️ Open-core | ✅ Yes | ✅ Yes |

Detailed comparisons:

- **[Pantavisor vs Yocto](/meta-pantavisor/getting-started/benchmarks/vs-yocto)** — why Pantavisor complements Yocto rather than replacing it
- **[Pantavisor vs Balena](/meta-pantavisor/getting-started/benchmarks/vs-balena)** — lightweight LXC vs Docker for embedded
- **[Pantavisor vs Buildroot](/meta-pantavisor/getting-started/benchmarks/vs-buildroot)** — composability vs minimalism
- **[Pantavisor vs Docker](/meta-pantavisor/getting-started/benchmarks/vs-docker)** — why Docker alone isn't enough for firmware

For the migration *path* off an image updater or container platform, see
[Migrate to Pantavisor](/meta-pantavisor/getting-started/migrate).

## Pantavisor vs image updaters (Mender / RAUC / SWUpdate)

Image updaters update **the image**: every change is a full-image event.
Pantavisor versions the device as content-addressed objects, so a change ships
only what actually changed.

Per-tool comparisons:

- **[Pantavisor vs Mender](/meta-pantavisor/getting-started/benchmarks/vs-mender)** — A/B full-image Artifacts vs object revisions
- **[Pantavisor vs RAUC](/meta-pantavisor/getting-started/benchmarks/vs-rauc)** — signed A/B slot bundles vs a signed device state
- **[Pantavisor vs SWUpdate](/meta-pantavisor/getting-started/benchmarks/vs-swupdate)** — scripted partition writes vs a declarative state

| Scenario | Image updater (full image) | Pantavisor (container layer) |
|---|---|---|
| Update payload size | full rootfs (~100s of MB) | changed layer only (~MB) |
| Downtime | reboot | no reboot for app updates |
| Flash writes | whole image | changed objects only |

> **📝 Note — measured numbers coming**
>
> The reproducible payload-size, update-time, and flash-write benchmarks (same
> hardware, same app change, image-updater vs Pantavisor) ship with the first
> public deliverable. Until then, treat the table above as the shape of the
> comparison, not as published figures.
