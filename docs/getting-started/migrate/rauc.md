---
title: RAUC to Pantavisor
sidebar_position: 2
description: Move from RAUC's A/B slot bundles to Pantavisor's content-addressed revisions — mapping meta-rauc, signed bundles, and slot switching to the Pantavisor model.
---

# RAUC to Pantavisor

RAUC updates **the image** through signed bundles (`.raucb`) written into A/B
**slots**, with the bootloader (U-Boot, Barebox, GRUB, or EFI) selecting the
active slot. Pantavisor replaces that model: it owns PID 1 and ships every
change as a content-addressed **revision**, transferring only changed objects
rather than a whole slot image — while keeping the signed-artifact guarantee
RAUC users rely on.

> **See also:** [Pantavisor vs RAUC](/meta-pantavisor/getting-started/benchmarks/vs-rauc) for the capability
> comparison.

## How the concepts map

| RAUC | Pantavisor | Notes |
|---|---|---|
| `meta-rauc` Yocto layer | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) | Swap the layer; Pantavisor builds the BSP, kernel, and containers. |
| A/B slots (`system.conf`) | [Revisions in the trail](/pantavisor/overview/revisions) | Rollback is to the previous revision; no mirrored full-rootfs slot pair. |
| Signed bundle (`.raucb`, X.509) | [Signed revision (`pvr sig`)](/meta-pantavisor/getting-started/security) | One signature transitively covers the whole device state. |
| Per-slot update of rootfs/app | [Containers](/meta-pantavisor/getting-started/develop) | Each component is an independent container, versioned on its own. |
| Bootloader slot switching | [Bootloader try/rollback + health-gated commit](/meta-pantavisor/getting-started/security/atomicity-and-trust) | A trial revision must pass health checks before promotion. |
| hawkBit / custom deploy server | [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) (optional) | Or deploy directly with `pvr` over the local network. |

## Migration path

1. **Rebuild with `meta-pantavisor`.** Replace `meta-rauc` and its
   `system.conf` slot definitions. See [Build with Yocto](/meta-pantavisor/overview/get-started).
2. **Re-express slots as containers.** A RAUC rootfs slot becomes a BSP
   container; application slots become application containers. See
   [Concepts](/pantavisor/overview) and
   [Develop applications](/meta-pantavisor/getting-started/develop).
3. **Carry over your signing keys.** Pantavisor signs revisions with X.509 keys
   via `pvr sig` — see [Security and compliance](/meta-pantavisor/getting-started/security).
4. **Flash a Pantavisor image** ([Install on hardware](/meta-pantavisor/getting-started/how-to-install)) and wire up
   deployments via `pvr` or [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub).

## What changes for your team

- **No doubled storage for the full rootfs.** Object-level revisions replace the
  A/B slot pair; only changed objects are written.
- **The base, kernel, and apps update through one mechanism** — a signed
  revision — instead of separate slot images.
- **Signing still gates trust**, but one signature covers the entire revision,
  not a per-bundle artifact.

> **⚠️ Warning — No hybrid stacks**
>
> There is no supported configuration where RAUC updates the kernel/BSP slot
> while Pantavisor handles apps. Pantavisor owns the whole device, including the
> base and kernel.
