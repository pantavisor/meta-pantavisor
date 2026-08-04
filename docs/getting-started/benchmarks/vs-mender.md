---
title: Pantavisor vs Mender
sidebar_position: 5
description: Mender ships full A/B rootfs images; Pantavisor ships content-addressed object revisions and updates the kernel/BSP as containers. Capability comparison and when each fits.
---

# Pantavisor vs Mender

## The short answer

**Mender updates the image. Pantavisor updates the state.** Mender keeps two
copies of the rootfs (an A/B slot pair) and writes a full Artifact into the
inactive slot. Pantavisor versions the device as content-addressed objects and
ships only what changed — and because the kernel/BSP is itself a container, it is
updated through the same mechanism as apps, with no separate updater running on
top of the OS.

Both give you atomic updates and rollback. The difference is the *unit* of update
(full rootfs vs object-level revision) and *scope* (apps-on-an-OS vs the whole
device including the base).

## At a glance

| Aspect | Mender | Pantavisor |
|---|---|---|
| Update model | A/B dual rootfs, full Artifact | Content-addressed state objects |
| Update unit | Full rootfs image (`.mender`) | Changed objects only |
| Delta updates | `mender-binary-delta` (commercial add-on) | Built-in object-level diffs |
| Kernel/BSP updates | Part of the rootfs image | A container in the same state |
| Partial / app updates | Update Modules | Native — every component is a container |
| Rollback | Commit after successful boot (+ state scripts) | Per-container health-gated commit + bootloader rollback |
| Update agent | Mender client (a service on the OS) | Pantavisor **is** PID 1 |
| Server | Mender Server (open-source edition available) / Hosted Mender | Pantahub (optional, open-source backend) |
| Storage cost | ~2× rootfs (A/B slots) | No full-rootfs mirror |
| Yocto layer | `meta-mender` | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) |

## Where the models differ

- **No doubled rootfs.** Mender's A/B layout reserves two full rootfs slots.
  Pantavisor keeps a trail of revisions made of shared content-addressed
  objects, so an app fix doesn't reserve or rewrite a whole second rootfs.
- **Object-level diffs are built in.** Mender transfers a full image unless you
  license `mender-binary-delta`. Pantavisor only transfers the objects whose
  hashes changed.
- **One mechanism for the whole device.** With Mender, the kernel/BSP rides
  inside the rootfs image and apps that need independent cadence use Update
  Modules. With Pantavisor, the BSP, kernel, services, and apps are all
  containers in one signed revision.
- **Per-container health gating.** Mender also commits only after a successful
  boot, and state scripts can add custom checks. Pantavisor's edge is
  granularity: each container declares a [`status_goal`](/meta-pantavisor/overview/glossary#status-goal), and the commit is held
  until every container reaches it — per-component health gating with no
  scripting.

## When Mender fits

- You have a working A/B rootfs pipeline and only ever ship full-image updates.
- App and kernel cadence are the same — you're happy reflashing the rootfs for any change.
- You want a mature, standalone updater you can bolt onto an existing OS image.

## When Pantavisor fits

- You want app fixes to ship as small container layers, not full-rootfs Artifacts.
- The **kernel/BSP must update through the same channel** as apps.
- You want object-level diffs without a commercial delta add-on.
- You want automatic, health-gated rollback for the whole device state.

## Key takeaway

> **Mender swaps the rootfs. Pantavisor versions the device.**

For the practical migration steps, see [Mender to Pantavisor](/meta-pantavisor/getting-started/migrate/mender).

> **⚠️ No hybrid stacks** — Pantavisor replaces Mender; it does not run alongside
> it with Mender owning the kernel/BSP. See [Migrate to Pantavisor](/meta-pantavisor/getting-started/migrate).
