---
title: Docker Compose to Pantavisor
sidebar_position: 5
description: Move a docker-compose deployment onto Pantavisor — keep the multi-container model, but gain atomic OTA updates, automatic rollback, and managed base/kernel for embedded devices.
---

# Docker Compose to Pantavisor

Docker Compose orchestrates multiple containers on a single host, but it is a
**local** tool: it does not deliver atomic OTA updates, roll back a failed
deployment, or manage the base OS and kernel. On an embedded device that needs
field updates, Compose is the app layer and nothing else. Pantavisor keeps the
multi-container model and adds the device runtime around it — as PID 1, it
manages the base, kernel, and apps as one signed, rollback-able revision.

> **See also:** [Pantavisor vs Docker](/meta-pantavisor/getting-started/benchmarks/vs-docker) — why Docker alone
> isn't enough for embedded firmware.

## How the concepts map

| Docker Compose | Pantavisor | Notes |
|---|---|---|
| `docker-compose.yml` services | [Containers in a revision](/meta-pantavisor/getting-started/develop) | Each service becomes a Pantavisor container. |
| `image:` reference | `pvr app add --from <image>` | Pulls the Docker/OCI image and converts it to an LXC container. |
| `environment:` / `volumes:` | `run.json` env + [`_config/` overlays](/meta-pantavisor/getting-started/develop/application/configure) | Per-container settings live in the revision. |
| Docker bridge network | Host network or [pv-xconnect](/meta-pantavisor/getting-started/develop/application/access-applications) | Containers reach each other over the host namespace or the service mesh. |
| `docker compose up` (manual) | `pvr post` / OTA via Pantahub | Updates are atomic revisions, not an in-place restart. |
| (no rollback) | [Automatic health-gated rollback](/meta-pantavisor/getting-started/security/atomicity-and-trust) | A failed revision is restored on the next boot. |
| (host OS managed separately) | BSP + kernel as containers in the revision | One mechanism for the whole device. |

## Migration path

1. **Add each service as a container** with
   `pvr app add --from <image> --platform <arch>`. See
   [Install with the pvr CLI](/meta-pantavisor/getting-started/develop/application/install/local-pvr).
2. **Port environment variables and volumes** into each container's `run.json`
   and the `_config/` overlay tree. See
   [Configure applications](/meta-pantavisor/getting-started/develop/application/configure).
3. **Replace the Compose network** with the host network namespace or
   [pv-xconnect](/meta-pantavisor/getting-started/develop/application/access-applications) for
   container-to-container links.
4. **Build and flash a Pantavisor image** for your target board
   ([Build with Yocto](/meta-pantavisor/overview/get-started), [Install on hardware](/meta-pantavisor/getting-started/how-to-install)).

## When Compose is still the right tool

If you are running containers on a **server or workstation** — not shipping an
embedded device that needs field updates — Pantavisor is likely more than you
need. Pantavisor's value is whole-device atomic updates, rollback, and base/BSP
management for fielded hardware. For local development or cloud workloads, stay
with Compose or a container orchestrator. See
[when *not* to use Pantavisor](/meta-pantavisor/getting-started/migrate/when-not-to-use).
