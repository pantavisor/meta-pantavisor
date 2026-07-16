---
title: Pantavisor vs Docker
sidebar_position: 4
description: Docker was built for servers, not embedded firmware. How Pantavisor's LXC system containers compare to Docker on resource use, atomic OTA, kernel updates, signed state, and offline operation.
---

# Pantavisor vs Docker — why Docker isn't enough for embedded firmware

## The short answer

**Docker is great. Docker on embedded firmware is a poor fit.**

Docker was designed for cloud and server workloads: ephemeral app containers,
large hosts, network-attached storage, and an always-running `dockerd` daemon.
Firmware on a 64–512 MB ARM device with eMMC, intermittent connectivity, and the
requirement to **never brick** has different constraints. Pantavisor is built for
those constraints from the ground up using LXC system containers.

Pantavisor still consumes Docker images — you don't lose your registry
investment — but the runtime, update model, and lifecycle are firmware-grade.

## At a glance

| Aspect | Docker | Pantavisor |
|---|---|---|
| Runtime | `dockerd` daemon + containerd | LXC, no daemon |
| Footprint | ~50–100 MB for a typical engine install | ~1 MB Pantavisor + LXC |
| Container model | Single-process app containers | System containers (init + services + fs) |
| Kernel/BSP | Lives on the host, not Docker's concern | A container in the same state |
| Update unit | Docker image layers | Content-addressed state objects |
| Atomic system update | ❌ Per-container only | ✅ Whole state revision |
| Automatic rollback on failure | ❌ DIY | ✅ Built-in (boot + `status_goal`) |
| Signed system state | ⚠️ Image signing only | ✅ PVS over state JSON |
| Offline / air-gapped use | ⚠️ Possible but awkward | ✅ Native (local clone, USB push, mirrored Pantahub) |
| Storage backend | overlay2 by default, ample writable storage assumed | overlayfs / squashfs / dm-verity / raw block |
| Boot dependency | Boots after host OS and host services | **Pantavisor *is* PID 1** |

## Why Docker hurts on embedded

### 1. The daemon tax

`dockerd` is a long-running root daemon. It eats RAM at idle, owns its own image
cache, and is a single point of failure for every container on the box. On a
server you don't notice; on a 256 MB device you do. Pantavisor has no daemon —
`pantavisor` *is* PID 1, and each LXC container is a normal supervised process
tree.

### 2. Kernel and BSP are outside the picture

Docker treats the kernel as a fixed property of the host. To change kernel,
drivers, or device tree you need a separate update mechanism (Mender, RAUC, A/B
partitions, custom scripts). With Pantavisor, **the BSP is just another container
in the state JSON** — kernel updates are the same operation as app updates.

### 3. No atomic system update

Updating multiple Docker containers at once is not atomic. If you update three
containers and the second fails, you're in a half-updated state. Pantavisor
switches the **entire system state** atomically — every container in the new
revision is in place, or none of them are.

### 4. Rollback is yours to build

Docker has no concept of "the previous good system state." When an update breaks
the device, you implement rollback yourself. Pantavisor monitors each container
against its declared `status_goal`; if any container fails to reach it, the
device automatically reverts to the last good state revision — no host-side
scripts required.

### 5. Storage assumptions don't hold

Docker defaults to overlay2 and assumes ample writable space for layer caches. Industrial
flash often is read-mostly, dm-verity protected, or organized as squashfs for
size. Pantavisor's volume model is flexible: containers can mount squashfs root
volumes, dm-verity-checked overlays, or persistent permanent volumes — whatever
the device's storage strategy demands.

### 6. Offline and air-gapped are second-class

Pulling Docker images on flaky cellular or in air-gapped networks is painful.
Pantavisor's content-addressed object store ships only changed hashes, supports
local mirrors of Pantahub, USB-stick deployment, and full offline operation as
first-class workflows.

## What Docker still does well

- **Developer ergonomics** — `docker run` is unbeatable for local iteration.
- **Image format and registries** — the OCI ecosystem is huge.
- **Cloud-native tooling** — Kubernetes, CI runners, sidecars, etc.

Pantavisor doesn't fight any of that. It treats Docker as an **input format**:

```bash
# Pull any Docker / OCI image and turn it into a Pantavisor container
pvr app add myapp --from nginx:latest
```

Your existing Dockerfiles, registries, and image build pipelines keep producing
artifacts. Pantavisor packages them into LXC system containers and ships them as
part of a signed, atomic state. See
[How does Pantavisor run Docker images?](/meta-pantavisor/getting-started/troubleshooting/faq).

## When Docker alone is fine

- Linux device with plenty of RAM/storage and a stable host OS you don't update often.
- Apps are stateless services and **rollback is handled at the orchestrator level** (k3s, Nomad).
- You don't need to update the kernel, drivers, or boot chain through the same pipeline.
- Connectivity is reliable.

## When you want Pantavisor instead

- Real embedded constraints (low RAM, eMMC, possibly read-only rootfs).
- The **kernel/BSP must be updateable** through the same OTA channel as apps.
- Failed updates must **never brick** — automatic rollback is non-negotiable.
- You need **signed, auditable system states** for compliance.
- Devices are deployed in the field with intermittent or air-gapped connectivity.
- You want **one update mechanism** for the whole system, not five glued together.

## Key takeaway

> **Docker ships apps to servers. Pantavisor ships firmware to devices.**

Use Docker for what it's great at — building images and running cloud workloads.
Use Pantavisor when the target is a constrained, long-lived, possibly
disconnected device that must update its kernel, services, and apps as one signed
unit and never brick.

## Next steps

- [Migrating a Docker Compose deployment](/meta-pantavisor/getting-started/migrate/docker-compose) — the practical path
- [Pantavisor vs Balena](/meta-pantavisor/getting-started/benchmarks/vs-balena) — the closest Docker-on-embedded competitor
- [What is Pantavisor?](/pantavisor/overview) — the architecture in depth
