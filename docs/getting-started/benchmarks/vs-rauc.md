---
title: Pantavisor vs RAUC
sidebar_position: 6
description: RAUC ships signed A/B slot bundles; Pantavisor ships signed content-addressed object revisions and updates the kernel/BSP as containers. Capability comparison and when each fits.
---

# Pantavisor vs RAUC

## The short answer

**RAUC updates A/B slots with signed bundles. Pantavisor updates a signed,
content-addressed state.** RAUC writes a signed bundle (`.raucb`) into an
inactive slot and the bootloader switches slots. Pantavisor versions the whole
device as content-addressed objects under one signature — and the kernel/BSP is a
container in that same state, not a separate slot.

Both give you signed, atomic updates with rollback. The difference is granularity
(full slot image vs object-level revision) and what the signature covers (a
bundle vs the entire device state).

## At a glance

| Aspect | RAUC | Pantavisor |
|---|---|---|
| Update model | A/B slots, signed bundle | Content-addressed state objects |
| Update unit | Slot image (`.raucb`; adaptive updates shrink downloads) | Changed objects only (transfer *and* storage) |
| Signing | X.509 over the bundle | PVS over the whole state JSON |
| Kernel/BSP updates | A slot image | A container in the same state |
| Rollback | Bootloader slot switch | Health-gated commit + bootloader rollback |
| Update agent | RAUC update handler | Pantavisor **is** PID 1 |
| Server | hawkBit / custom | Pantahub (optional, open source) |
| Storage cost | ~2× slots (A/B) | No full-rootfs mirror |
| Yocto layer | `meta-rauc` | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) |

## Where the models differ

- **One signature for the whole device.** RAUC signs each bundle. Pantavisor
  signs the entire revision (PVS over the state JSON), so one signature
  transitively covers every object on the device.
- **No doubled slots.** RAUC's adaptive updates (block-hash-index) can reduce
  the *download* size, but each update still writes a whole slot and the A/B
  layout reserves roughly 2× storage. Pantavisor's revision trail shares
  content-addressed objects, so only changed objects are transferred *and*
  stored.
- **The base is part of the same state.** A RAUC rootfs slot becomes a BSP
  container; application slots become application containers — all in one
  revision instead of separate slot images.
- **Health-gated rollback.** RAUC relies on bootloader slot switching. Pantavisor
  additionally holds the commit until each container reaches its `status_goal`.

## When RAUC fits

- You have an established A/B slot layout and bootloader integration.
- Full-slot images are an acceptable update unit.
- You want a focused, standalone signed-update mechanism on an existing OS.

## When Pantavisor fits

- You want one signature over the **entire device state**, not per-bundle.
- You want object-level diffs instead of full slot images, with no doubled storage.
- The **kernel/BSP must update through the same channel** as apps.
- You want automatic, health-gated rollback for the whole state.

## Key takeaway

> **RAUC switches signed slots. Pantavisor versions a signed device.**

For the practical migration steps, see [RAUC to Pantavisor](/meta-pantavisor/getting-started/migrate/rauc), and
for the signing/trust model see [Security and compliance](/meta-pantavisor/getting-started/security).

> **⚠️ No hybrid stacks** — Pantavisor replaces RAUC; it does not run alongside it
> with RAUC owning the kernel/BSP slot. See [Migrate to Pantavisor](/meta-pantavisor/getting-started/migrate).
