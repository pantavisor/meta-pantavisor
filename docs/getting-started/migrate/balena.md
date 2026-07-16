---
title: Balena to Pantavisor
sidebar_position: 4
description: Move from Balena's Docker-based fleet model to Pantavisor — keep the multi-container app model, but gain a PID 1 runtime that updates the base and kernel as containers too.
---

# Balena to Pantavisor

Balena is the closest of the migration sources to Pantavisor: both run your
application as **containers** on the device. The difference is ownership. Balena
runs containers (under balenaEngine, a Docker fork) on top of a host OS that is
updated separately via hostOS/hostApp mechanisms. Pantavisor **is** PID 1 and
treats *everything* as a container — the BSP, the kernel, system services, and
your apps — so the base and the apps update through one signed revision.

> **See also:** [Pantavisor vs Balena](/meta-pantavisor/getting-started/benchmarks/vs-balena) for the capability
> comparison — footprint, openness, and OTA model.

## How the concepts map

| Balena | Pantavisor | Notes |
|---|---|---|
| balenaOS (host OS) + hostApp updates | Pantavisor as PID 1, BSP as a container | The base and kernel are part of the same revision as your apps — no separate host-OS update path. |
| `docker-compose.yml` multi-container app | [Containers in a revision](/meta-pantavisor/getting-started/develop) | Each service becomes a Pantavisor container. |
| balenaEngine (Docker fork) | LXC | On-device containers run under LXC, not a Docker daemon. See the [FAQ](/meta-pantavisor/getting-started/troubleshooting/faq). |
| `balena push` / release | `pvr commit` + `pvr post` / push to Pantahub | The unit of update is a content-addressed revision. |
| balenaCloud fleet management | [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) (optional) | Or manage devices directly with `pvr` over the local network. |
| Delta layer updates | Object-level diffs (built in) | Only changed content-addressed objects are transferred. |

## Migration path

1. **Translate your compose services to containers.** Each service image is
   added with `pvr app add --from <image>` — Pantavisor converts it to an LXC
   container. See [Install with the pvr CLI](/meta-pantavisor/getting-started/develop/application/install/local-pvr).
2. **Move inter-service communication to the host network or
   [pv-xconnect](/meta-pantavisor/getting-started/develop/application/access-applications).** Containers that
   shared a Docker network can use the host network namespace or the xconnect
   service mesh.
3. **Build your base with [`meta-pantavisor`](/meta-pantavisor/overview/get-started)** instead of relying on a
   separately-updated host OS.
4. **Flash a Pantavisor image** ([Install on hardware](/meta-pantavisor/getting-started/how-to-install)) and manage
   the fleet via [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub).

## What changes for your team

- **The host OS stops being a separate update channel.** Base, kernel, and apps
  are one revision, rolled back atomically together if needed.
- **No Docker daemon on the device** — containers run under LXC, supervised by
  PID 1.
- **You keep the multi-container mental model**, but gain whole-device
  atomicity and rollback.

> **📝 Note — Docker images still work**
>
> You do not have to rebuild your images. `pvr app add --from <image>` pulls a
> standard Docker/OCI image and converts it to a Pantavisor container — see
> [How does Pantavisor run Docker images?](/meta-pantavisor/getting-started/troubleshooting/faq).
