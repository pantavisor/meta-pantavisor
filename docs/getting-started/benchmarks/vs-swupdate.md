---
title: Pantavisor vs SWUpdate
sidebar_position: 7
description: SWUpdate writes partition images described by a sw-description script; Pantavisor ships a declarative content-addressed state and updates the kernel/BSP as containers. When each fits.
---

# Pantavisor vs SWUpdate

## The short answer

**SWUpdate writes images to partitions from a script. Pantavisor switches a
declarative, content-addressed state.** SWUpdate is flexible and scriptable: a
`sw-description` file lists images and the partitions or handlers they are written
to, optionally in a double-copy (A/B) layout. Pantavisor describes the whole
device declaratively as one signed state JSON and transfers only the objects that
changed.

Both are capable update engines. The difference is that SWUpdate is a
script-driven partition writer you assemble, while Pantavisor is a declarative
state manager that owns the device as PID 1.

## At a glance

| Aspect | SWUpdate | Pantavisor |
|---|---|---|
| Update model | `sw-description` + images to partitions | Content-addressed state objects |
| Update unit | Partition images per `sw-description` | Changed objects only |
| Configuration | Hand-written `sw-description` + handlers | Declarative state JSON |
| Kernel/BSP updates | A partition image | A container in the same state |
| Rollback | Requires bootloader-environment integration (built-in `ustate` support) | Health-gated commit + bootloader rollback |
| Update agent | SWUpdate (a service on the OS) | Pantavisor **is** PID 1 |
| Server | hawkBit / custom | Pantahub (optional, open source) |
| A/B | Optional double-copy partitions | Revisions in the trail |
| Yocto layer | `meta-swupdate` | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) |

## Where the models differ

- **Declarative vs scripted.** SWUpdate's `sw-description` is a per-update recipe
  of images and handlers you maintain. Pantavisor's revision is a declarative
  manifest of the whole device — there is no per-update script to write.
- **Object-level, not partition-level.** SWUpdate's open-source delta handler
  (zchunk-based) can shrink downloads, but a changed partition is still
  rewritten whole on flash. Pantavisor transfers *and* writes only the changed
  content-addressed objects.
- **The base is part of the same state.** A SWUpdate image/handler entry becomes
  a container or a `_config/` overlay rather than a partition write.
- **Rollback is built in.** SWUpdate provides `ustate` support, but rollback
  still requires bootloader-environment integration. Pantavisor's rollback is
  automatic and health-gated on each container's `status_goal`.

## When SWUpdate fits

- You need very fine-grained, scriptable control over exactly which partitions
  and handlers run.
- You already maintain `sw-description` collections and a bootloader rollback scheme.
- You want a standalone updater on an existing OS image.

## When Pantavisor fits

- You'd rather describe the device declaratively than maintain update scripts.
- You want object-level transfer instead of whole-partition images.
- The **kernel/BSP must update through the same channel** as apps.
- You want automatic, health-gated rollback without custom scripting.

## Key takeaway

> **SWUpdate scripts partition writes. Pantavisor switches a declarative state.**

For the practical migration steps, see [SWUpdate to Pantavisor](/meta-pantavisor/getting-started/migrate/swupdate).

> **⚠️ No hybrid stacks** — Pantavisor replaces SWUpdate; it does not run
> alongside it with SWUpdate owning the kernel/BSP partitions. See
> [Migrate to Pantavisor](/meta-pantavisor/getting-started/migrate).
