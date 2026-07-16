---
title: SWUpdate to Pantavisor
sidebar_position: 3
description: Move from SWUpdate's sw-description image collections to Pantavisor's content-addressed revisions — mapping meta-swupdate, handlers, and hawkBit to the Pantavisor model.
---

# SWUpdate to Pantavisor

SWUpdate updates **the image**: a `sw-description` file lists images and the
partitions or handlers they are written to, optionally in a double-copy (A/B)
layout, often orchestrated by a hawkBit server. It is flexible and scriptable,
but the unit of update is still a set of partition images. Pantavisor replaces
that model — it owns PID 1 and ships every change as a content-addressed
**revision**, transferring only the objects that changed.

> **See also:** [Pantavisor vs SWUpdate](/meta-pantavisor/getting-started/benchmarks/vs-swupdate) for the
> capability comparison.

## How the concepts map

| SWUpdate | Pantavisor | Notes |
|---|---|---|
| `meta-swupdate` Yocto layer | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) | Swap the layer; Pantavisor builds the BSP, kernel, and containers. |
| `sw-description` + images | A [`pvr` revision](/pantavisor/overview/revisions) | The whole device state is one signed, diffable manifest, not a script over partitions. |
| Double-copy (A/B) partitions | [Revisions in the trail](/pantavisor/overview/revisions) | Rollback is to the previous revision; no duplicated partition set. |
| Image handlers (rootfs, raw, files) | [Containers + config overlays](/meta-pantavisor/getting-started/develop) | Components are containers; file changes are `_config/` overlays. |
| CMS / signed `sw-description` | [Signed revision (`pvr sig`)](/meta-pantavisor/getting-started/security) | One signature covers the entire revision. |
| hawkBit deployment server | [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) (optional) | Or deploy directly with `pvr` over the local network. |

## Migration path

1. **Rebuild with `meta-pantavisor`.** Replace `meta-swupdate` and your
   `sw-description` collections. See [Build with Yocto](/meta-pantavisor/overview/get-started).
2. **Map images to containers.** Each image/handler entry becomes a container
   (BSP or application) or a `_config/` file overlay rather than a partition
   write. See [Concepts](/pantavisor/overview) and
   [Configure applications](/meta-pantavisor/getting-started/develop/application/configure).
3. **Flash a Pantavisor image** ([Install on hardware](/meta-pantavisor/getting-started/how-to-install)) and wire up
   deployments via `pvr` or [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub).

## What changes for your team

- **No update script to maintain.** The revision manifest describes the whole
  device declaratively; you do not hand-write per-partition image lists.
- **Updates are object-level in transfer and on flash.** SWUpdate's delta
  handler (zchunk) can shrink downloads, but a changed partition is still
  rewritten whole; Pantavisor writes only the changed objects. See the
  [benchmarks](/meta-pantavisor/getting-started/benchmarks).
- **Rollback is automatic and health-gated** rather than dependent on your
  `sw-description` logic and bootloader scripting.

> **⚠️ Warning — No hybrid stacks**
>
> Do not keep SWUpdate writing the kernel/BSP partitions while Pantavisor
> handles apps. Pantavisor owns the whole device as a single signed revision.
