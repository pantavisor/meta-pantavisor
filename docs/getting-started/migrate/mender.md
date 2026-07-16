---
title: Mender to Pantavisor
sidebar_position: 1
description: Move from Mender's A/B full-image updates to Pantavisor's content-addressed, object-level revisions — mapping meta-mender, Artifacts, and the Mender server to the Pantavisor model.
---

# Mender to Pantavisor

Mender updates **the image**: it keeps two copies of the rootfs (an A/B slot
pair) and writes a full Artifact into the inactive slot, then switches the
bootloader flag. Pantavisor replaces that model entirely — it owns PID 1 and
ships every change as a content-addressed **revision**, transferring only the
objects that actually changed. There is no A/B duplication of the whole rootfs
and no separate updater running on top of the OS.

> **See also:** [Pantavisor vs Mender](/meta-pantavisor/getting-started/benchmarks/vs-mender) for the capability
> comparison.

## How the concepts map

| Mender | Pantavisor | Notes |
|---|---|---|
| `meta-mender` Yocto layer | [`meta-pantavisor`](/meta-pantavisor/overview/get-started) | Swap the layer; Pantavisor builds the BSP, kernel, and containers. |
| A/B rootfs slots | [Revisions in the trail](/pantavisor/overview/revisions) | Rollback is to the previous revision, not a mirrored partition — no doubled storage for the full rootfs. |
| Mender Artifact (`.mender`) | A `pvr` revision (`pvr commit` + `pvr post`) | The unit of update is a signed, diffable revision. |
| `mender-binary-delta` (commercial delta) | Object-level diffs (built in) | Only changed content-addressed objects are transferred — no separate delta add-on. |
| Update Modules (partial/app updates) | [Containers](/meta-pantavisor/getting-started/develop) | Every component is already an independent container; app updates never touch the base. |
| Mender client (a service on the OS) | Pantavisor **is** PID 1 | No agent layered on top — the runtime and the updater are the same process. |
| Mender server / Hosted Mender | [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) (optional) | Or deploy directly over the local network with `pvr`; the cloud is not required. |
| Commit after successful boot (+ state scripts) | [Health-gated commit + bootloader try/rollback](/meta-pantavisor/getting-started/security/atomicity-and-trust) | Both gate the commit on a healthy boot; Pantavisor gates per container on its `status_goal`, with no scripts to write. |

## Migration path

1. **Rebuild with `meta-pantavisor`.** Replace `meta-mender` in your Yocto
   configuration. See [Build with Yocto](/meta-pantavisor/overview/get-started) and
   [Get started with meta-pantavisor](/meta-pantavisor/overview/get-started).
2. **Decompose the rootfs into containers.** What was a single Mender rootfs
   becomes a BSP container plus one or more application containers. See
   [Concepts](/pantavisor/overview) and
   [Develop applications](/meta-pantavisor/getting-started/develop).
3. **Flash a Pantavisor image** to your board. See
   [Install on hardware](/meta-pantavisor/getting-started/how-to-install).
4. **Wire up deployments.** Push revisions over the local network with `pvr`,
   or claim the device on [Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub)
   for remote OTA.

## What changes for your team

- **App fixes stop being full-image events.** A one-line change ships as a small
  container layer, not a full rootfs Artifact. See the
  [benchmarks](/meta-pantavisor/getting-started/benchmarks) for the size and time difference.
- **The base and kernel are updated the same way** — as containers in a
  revision — so you do not run an A/B image updater underneath Pantavisor.
- **Rollback stays automatic** — and health gating is per container
  (`status_goal`) rather than per boot, with no state scripts to maintain.

> **⚠️ Warning — No hybrid stacks**
>
> Do not keep Mender updating the rootfs/kernel while Pantavisor handles apps.
> That reintroduces whole-image updates and breaks the single signed-revision
> model. Pantavisor replaces Mender, it does not run alongside it.
