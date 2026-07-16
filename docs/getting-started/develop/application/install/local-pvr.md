---
title: Install with the pvr CLI
sidebar_position: 41
description: Install an application on Pantavisor with the pvr CLI — clone the device, add a container from a Docker image, commit, and deploy a new revision over the local network.
---

The `pvr` CLI lets you add a Docker Hub image as a Pantavisor container, commit the change locally, and deploy it to the device over the local network — all without touching the device directly.

**Prerequisites**: `pvr` installed on your workstation ([install guide](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli)) and the device reachable on the local network.

---

## 1 — Clone the Device

Clone the device's current revision to your workstation. Pantavisor exposes its state over HTTP on port 12368.

```bash
pvr clone http://<device-ip>:12368/cgi-bin mydevice
cd mydevice
```

The checkout mirrors the live device state — all containers, their rootfs images, LXC configs, and manifests.

## 2 — Add the New Container

Use `pvr app add` to pull a Docker Hub image and convert it to a Pantavisor container. Specify `--platform` to match your device architecture.

```bash
# ARM64 device (e.g. Raspberry Pi 4, iMX8)
pvr app add tailscale --from tailscale/tailscale --platform linux/arm64

# ARM32 device (e.g. iMX6)
pvr app add tailscale --from tailscale/tailscale --platform linux/arm/v7
```

`pvr app add` pulls the image, converts it to a SquashFS rootfs, and creates the container's directory with:

```
tailscale/
├── root.squashfs               ← container filesystem
├── root.squashfs.docker-digest ← image digest for update tracking
├── src.json                    ← image source and template arguments
├── run.json                    ← Pantavisor runtime manifest
└── lxc.container.conf          ← LXC runtime configuration
```

## 3 — Stage and Commit

Check what was added:

```bash
pvr status
```

Expected output:

```
A tailscale/lxc.container.conf
A tailscale/root.squashfs
A tailscale/root.squashfs.docker-digest
A tailscale/run.json
A tailscale/src.json
```

Stage and commit the new revision:

```bash
pvr add .
pvr commit -m "add Tailscale container"
```

## 4 — Deploy to the Device

Post the new revision to the device's pvr endpoint — the same URL you cloned from:

```bash
pvr post http://<device-ip>:12368
```

Pantavisor downloads the new container objects, writes them as a pending revision, and transitions into it — a full reboot only happens when a `system` restart-policy container or the BSP changed. If the new revision runs cleanly, it becomes the new permanent state.

## 5 — Verify

After the transition, confirm the container is running:

```bash
# From the device console (serial or SSH)
lxc-ls -f

# Or via pvcontrol
pvcontrol container ls
```

The new container should show as `RUNNING`. You can also check from the pvtx web UI at `http://<device-ip>:12368/app`.
