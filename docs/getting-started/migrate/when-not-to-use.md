---
title: When not to use Pantavisor
sidebar_position: 6
description: An honest list of cases where Pantavisor is not the right fit — non-Linux targets, server/cloud workloads, devices where you cannot own PID 1, and constraints that rule out a full replacement.
---

# When *not* to use Pantavisor

Pantavisor is a strong fit when you ship **Linux devices in the field** and want
whole-device atomic updates, automatic rollback, and unified base/kernel/app
management. It is not the right tool for every job. Being explicit about the
boundaries is part of earning trust at PID 1.

## Pantavisor is probably not for you if…

- **Your target is not Linux.** Pantavisor is the Linux init process and
  container runtime. Bare-metal MCUs, RTOS targets, and non-Linux systems are
  out of scope.
- **You are running containers on a server or in the cloud.** For data-center
  or workstation workloads, use Docker, Podman, or a Kubernetes-class
  orchestrator. Pantavisor's value is *device* lifecycle management, not cluster
  scheduling. See [Docker Compose to Pantavisor](/meta-pantavisor/getting-started/migrate/docker-compose).
- **You cannot own PID 1 or reflash the device.** Pantavisor replaces the init
  system and the update stack. If a vendor BSP, a certification regime, or a
  contract forces you to keep an existing init/updater that owns the device, you
  cannot run Pantavisor as intended — and there is **no supported hybrid** where
  an A/B image updater sits underneath it.
- **You only ever update one app and never the base, on a pipeline you cannot
  change.** If a working, frozen image-update process already meets your needs
  and you have no appetite to re-architect the device, the migration cost may
  not pay off. (If you *can* change it, the [benchmarks](/meta-pantavisor/getting-started/benchmarks) show what
  you would gain.)

## Things that are **not** reasons to avoid Pantavisor

- *"My apps are Docker images."* Pantavisor pulls standard Docker/OCI images and
  converts them to containers — see the
  [FAQ](/meta-pantavisor/getting-started/troubleshooting/faq).
- *"I need signed, secure updates."* Pantavisor signs whole revisions with X.509
  keys and supports dm-verity, dm-crypt, and secure boot (on boards with
  verified-boot support). See
  [Security and compliance](/meta-pantavisor/getting-started/security).
- *"I need the base/kernel updated too."* That is exactly what Pantavisor does —
  the BSP and kernel ship as containers in the same revision as your apps.

If you are unsure whether your case fits, ask in the
[community](/meta-pantavisor/getting-started/community) — a short description of your device and update
constraints is usually enough to get a clear answer.
