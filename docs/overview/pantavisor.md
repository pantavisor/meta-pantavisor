# Pantavisor

Pantavisor is an open-source, container-based embedded Linux system runtime.
It runs on top of a minimal initramfs and manages the device lifecycle —
booting containers, handling OTA updates, and exposing a REST API for local
and cloud control — without requiring a conventional root filesystem.

## Core ideas

**Everything is a container.** Applications, BSP components (kernel, firmware,
modules), and system services all run as isolated LXC containers. The host
initramfs only contains Pantavisor itself; user space lives entirely in
containers.

**Atomic, rollback-capable updates.** Device state is tracked in a versioned
trail (`/trails/`). Each update produces a new revision. If a revision fails
to boot, Pantavisor rolls back to the last known-good state automatically.

**Cloud-connected by design.** Devices register with
[Pantahub](https://pantahub.com) and receive OTA updates, logs, and remote
control through the cloud. The `pvr` CLI tool is used to build and push
container state from a developer workstation.

## Getting started

| Resource | Description |
|---|---|
| [pantavisor.io — Learn & Concepts](https://pantavisor.io/learn/concepts/index.html) | High-level introduction to Pantavisor concepts, architecture, and use cases — start here |
| [docs.pantahub.com](https://docs.pantahub.com/) | Full reference documentation: API, pvr CLI, container authoring, OTA, BSP integration |

## Key components

### Pantavisor runtime

The core daemon (`pantavisor`) runs in the initramfs and is responsible for:

- Mounting the storage partition and reading device state
- Starting and supervising LXC containers in dependency order
- Communicating with Pantahub for OTA update delivery
- Exposing the local control socket (`pvcontrol`)

### pvr — the Pantavisor client CLI

`pvr` is the developer-facing tool for working with Pantavisor state. It is
used to initialise a device state repository, add containers, commit changes,
and push/pull from Pantahub — analogous to `git` but for device state.

### pv-xconnect — service mesh

`pv-xconnect` mediates container-to-container communication without requiring
a shared network namespace. Supported transport types:

| Type | Description |
|---|---|
| `unix` | Raw Unix socket proxy with namespace injection |
| `rest` | HTTP-over-UDS with identity headers (`X-PV-Client`, `X-PV-Role`) |
| `dbus` | Policy-aware D-Bus proxy with interface filtering |
| `drm` | DRM device node injection for graphics (`card0`, `renderD128`) |
| `wayland` | Compositor access for isolated UI rendering |

### pvcontrol — local REST API

The `pvcontrol` socket exposes a REST API for querying and controlling the
running device state. Useful for scripting and integration:

```bash
# List running containers
pvcontrol daemons ls

# Inspect the xconnect service graph
pvcontrol graph ls
```

## Device state model

A Pantavisor device holds a sequence of *revisions*, each describing the full
set of running containers and BSP components. The current revision lives in
`/trails/0/` and contains:

- `bsp/` — kernel image, initramfs, device tree, modules, firmware squashfs files
- `<container>/` — per-container rootfs and metadata
- `device.json` — device-level configuration
- `#spec` — format version marker used by pvr

## OTA updates

Updates are delivered as diffs against the current revision. Pantavisor
downloads the new objects, verifies signatures (when configured), writes them
to a pending revision, and triggers a reboot to apply. If the new revision
reports healthy, it becomes the permanent state; otherwise the previous
revision is restored.

## Security features

| Feature | BitBake variable | Description |
|---|---|---|
| dm-crypt | `dm-crypt` | Storage encryption |
| dm-verity | `dm-verity` | Container rootfs integrity verification |
| Signed state | `pvr sig` | PVR state signing with X.509 keys |
| Secure boot | platform-dependent | U-Boot verified boot / FIT image signing |
