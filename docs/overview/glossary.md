---
title: Glossary
sidebar_position: 20
description: Definitions of the core Pantavisor terms — revision, trail, state, BSP, container, pvrexport, xconnect, and the tools around them.
---

# Glossary

The terms you will meet throughout these docs, in alphabetical order. Where a
term has a dedicated page, the entry links to it.

### AppEngine

Pantavisor packaged to run inside a Docker container on an x86 workstation —
a full device without hardware, used for development and CI. See
[run Pantavisor in Docker](/meta-pantavisor/getting-started/how-to-install/docker).

### Auto-recovery

Per-container restart handling: when a container exits, Pantavisor retries it
according to its `auto_recovery` settings (retries, delay, backoff); if a new
revision never reaches its status goals, the device rolls back to the last
good revision. See [what is Pantavisor](../../pantavisor/overview/index.md).

### BSP (board support package)

The hardware part of a revision — kernel, device trees, firmware, and kernel
modules — packaged as the `bsp/` part of the state with its own `run.json`.
Built from [meta-pantavisor](/meta-pantavisor/overview/get-started).

### Container

An LXC container defined as a part of the device state: a squashfs root
filesystem plus a `run.json` runtime manifest (and a `src.json` recording
where it came from). Apps, system services, and management tools are all
containers. **Note:** older generated reference pages call containers
*platforms* — same thing.

### Debug shell

The root shell on the device's serial console. It sees Pantavisor's control
tree at `/pv/` (inside a container the same tree is mounted at
`/pantavisor/`). See [serial port access](/meta-pantavisor/getting-started/operate/device-access/serial-port).

### Factory containers

Containers bundled into the flashed starter image (revision 0), as opposed to
apps installed later over the air. Selected at build time via
`PVROOT_CONTAINERS` in the image recipe.

### Groups

Named startup groups that order container boot (and carry roles such as
management). Defined in the state's `groups.json`; inspect them with
`pvcontrol groups ls`.

### Object

A content-addressed file blob, named by its SHA-256 hash. Revisions reference
objects rather than containing them, so unchanged files are stored and
transferred exactly once.

### Pantahub

The optional cloud backend (also branded **Pantacor Hub**) at
[hub.pantacor.com](https://hub.pantacor.com): device claiming, fleet
management, remote updates, and log streaming. Devices work fully without it.

### pv-ctrl

The local Unix socket on which Pantavisor exposes its REST API (`/pv/pv-ctrl`
from the debug shell, `/pantavisor/pv-ctrl` from a management container).
`pvcontrol` is the CLI for it.

### pvcontrol

On-device CLI for the pv-ctrl API: list containers, run revisions, manage
metadata, send commands. See [pvcontrol](/meta-pantavisor/getting-started/develop/cli-tools/pvcontrol).

### pvr

The workstation CLI with git-like semantics: `clone` a device's state, `add`
and `commit` changes, `post` them back to the device or to Pantahub. See the
[pvr CLI](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli).

### pvrexport

A tarball of one or more state parts (an app or a BSP) produced by `pvr
export` or a meta-pantavisor container recipe, deployable onto any device via
pvtx, the web UI, or `pvr`.

### pvtx

Pantavisor's on-device update-transaction tool: begin a transaction, add
parts, commit — atomically. It also serves the device web UI on port 12368
(`/app`). See the [pvtx web UI](/meta-pantavisor/getting-started/operate/device-access/pvtx-ui).

### Restart policy

Per-container update behavior: `system` containers require a reboot to
update; `container` ones are restarted in place, making the update a
non-reboot transition.

### Revision

A numbered, immutable snapshot of the complete device state — BSP and all
containers. Revision 0 is the factory state; updates create new revisions and
the device can atomically run or roll back to any of them.

### State (state JSON)

The JSON document that fully describes a revision — every part, file, and
manifest, referencing objects by hash. Identified by `#spec`
(`pantavisor-service-system@1`). The authoritative schema is the
[state format reference](/pantavisor/reference/pantavisor-state-format-v2).

### Status goal

The state a container must reach (e.g. started) for an update to count as
successful. If goals are not met within the stability window, the update is
not committed and the device rolls back.

### Trail

The ordered history of a device's revisions — `trails/` on the device's
storage, mirrored per device on Pantahub.

### xconnect

Pantavisor's inter-container service connectivity: containers declare the
services they provide and require in `services.json`
(`service-manifest-xconnect@1`), and Pantavisor wires them together. See the
[xconnect reference](/pantavisor/overview/xconnect).
