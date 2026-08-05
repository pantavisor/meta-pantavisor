---
title: Configuration
description: How a Pantavisor revision is laid out on disk — the pvr checkout structure, the run.json container manifest, device.json, and _config overlays.
---

A Pantavisor device revision is described by a single JSON manifest where every
key is a **file path** and every value is either a nested configuration object or
the SHA256 of a binary artifact. When you `pvr clone` a device, that manifest is
expanded into a working directory you can edit. This page covers the real
layout; for the exhaustive field-by-field schema see the reference
[state format](/pantavisor/reference/pantavisor-state-format-v2), and see the
[on-device tools (pvtx, pvcontrol)](/pantavisor/tools/pantavisor-tools)
reference for working with revisions on the device itself.

## Repository layout

A `pvr` checkout mirrors the device revision:

```
my-device/
├── #spec                       # parser version — "pantavisor-service-system@1"
├── bsp/
│   ├── run.json                # kernel, initrd, modules, firmware, DTB/FIT paths
│   └── ...                     # the BSP artifacts (squashfs, kernel image, …)
├── <container>/                # one directory per container (e.g. network, sensor-app)
│   ├── run.json                # container manifest (see below)
│   ├── lxc.container.conf      # LXC runtime configuration
│   ├── root.squashfs           # read-only container rootfs
│   ├── root.squashfs.docker-digest
│   └── services.json           # (optional) services this container exports to xconnect
├── device.json                 # disks, orchestration groups, Pantavisor volumes
├── _config/<container>/<path>  # files injected into a container's rootfs (overlay)
├── _sigs/<container>.json      # (optional) signature over the container's artifacts
└── .pvr/
    ├── json                    # the full revision manifest (state.json)
    ├── config                  # repository configuration
    └── objects/                # content-addressed objects
```

> **📝 Note**
>
> There is no `pvr.json` and no top-level `containers/` or `volumes/` directory.
> Each container is a directory at the **root** of the checkout; the full
> revision manifest is `.pvr/json`.

## Container manifest — `<container>/run.json`

Each container's `run.json` (`#spec: "service-manifest-run@1"`) configures how
Pantavisor runs it:

```json
{
  "#spec": "service-manifest-run@1",
  "name": "sensor-app",
  "type": "lxc",
  "config": "lxc.container.conf",
  "root-volume": "root.squashfs",
  "group": "app",
  "status_goal": "STARTED",
  "restart_policy": "container",
  "storage": {
    "/var/lib/sensor": { "persistence": "permanent" }
  },
  "auto_recovery": {
    "policy": "on-failure",
    "max_retries": 5,
    "retry_delay": 5,
    "backoff_factor": 2.0,
    "backoff_policy": "10min"
  }
}
```

Key fields:

| Field | Purpose |
|---|---|
| `name` | Logical container name. |
| `type` | Runtime — currently `lxc`. |
| `config` | Path to the LXC configuration file. |
| `root-volume` | Path to the rootfs squashfs artifact. |
| `group` | Orchestration group (defined in `device.json`); inherits the group's defaults. |
| `status_goal` | Target state — `MOUNTED`, `STARTED`, or `READY`. |
| `restart_policy` | `container` (restart the container) or `system` (reboot the device) on crash. |
| `storage` | Per-path persistence: `permanent` (survives updates), `revision` (survives reboots), `boot` (volatile). |
| `auto_recovery` | Restart behaviour on failure — see below. |
| `services` | xconnect service requirements (`required`/`optional`). |

### Auto-recovery

`auto_recovery` controls restart-on-failure. If a container omits it, it
inherits the policy of its `group` (all-or-nothing).

| Field | Default | Meaning |
|---|---|---|
| `policy` | `no` | `no`, `always`, `on-failure`, `unless-stopped`. |
| `max_retries` | `0` | Max restart attempts (`0` = unlimited). |
| `retry_delay` | `0` | Seconds before the first restart. |
| `backoff_factor` | `1.0` | Multiplier applied to `retry_delay` each retry. |
| `reset_window` | `0` | Uptime (s) after which the retry counter resets. |
| `stable_timeout` | `0` | Seconds the container must survive to gate the update commit. |
| `backoff_policy` | `reboot` | After retries exhausted — `reboot`, `never`, or a duration (`10min`, `1h`). |

> **📝 Note**
>
> The current implementation of `on-failure` does not distinguish exit codes —
> it behaves like `always`.

## Device manifest — `device.json`

`device.json` holds device-level infrastructure: storage `disks`, orchestration
`groups` (with their default `status_goal`, `restart_policy`, `timeout`, and
`auto_recovery`), and Pantavisor's own persistent `volumes`. See the reference
[state format](/pantavisor/reference/pantavisor-state-format-v2) for the
disk and group schemas.

## File overlays — `_config/<container>/`

Container root filesystems (`root.squashfs`) are read-only. To add or change a
file inside a container, place it under `_config/<container>/<path>`, mirroring
the path inside the container. Pantavisor overlays it onto the rootfs at startup.
This is how you add SSH keys, drop-in config files, or scripts without rebuilding
the image — see [Configure applications](/meta-pantavisor/getting-started/develop/application/configure).

## Editing and applying changes

Edit these files in your `pvr` checkout, then commit and post a new revision:

```bash
pvr add .
pvr commit -m "configure sensor-app auto-recovery"
pvr post http://<device-ip>:12368
```

Pantavisor applies the new revision atomically and rolls back automatically if it
fails its health checks.
