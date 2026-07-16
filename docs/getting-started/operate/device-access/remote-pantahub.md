---
title: Remote Access via Pantahub
sidebar_position: 5
description: Learn how to access, monitor, and update your Pantavisor devices remotely using Pantahub and the PVR CLI tool.
---

Once a device is claimed on Pantahub and connected to the internet, you can manage it from anywhere using the `pvr` CLI. The device polls Pantahub for new revisions and applies OTA updates automatically — no local network access required.

## 1 — Claim the Device

Before remote management is possible the device must be registered. Read the device ID and challenge token from the [serial console debug shell](./serial-port):

```bash
cat /pv/device-id
cat /pv/challenge
```

Log in to [hub.pantacor.com](https://hub.pantacor.com), go to **Claim a Device** on the Devices page, and enter both values. Once claimed the device appears in your account and its online status updates in real time.

## 2 — Authenticate pvr

On your workstation, log in to Pantahub:

```bash
pvr login
```

Verify the session:

```bash
pvr whoami
```

## 3 — View Your Devices

List all devices in your account:

```bash
pvr device ps
```

This shows each device's nickname, Pantahub ID, current revision, and update status.

## 4 — Remote OTA Updates

Clone the device's state over the internet, make changes, and deploy back:

```bash
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME my-device
cd my-device

# Make changes — add a container, edit run.json, update config overlays
pvr app add myapp --from myorg/myapp:latest --platform linux/arm64
pvr add .
pvr commit -m "add myapp"
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

Pantahub queues the new revision. The device downloads only the changed objects (not a full image) and applies the update on the next poll cycle. Monitor progress from the device dashboard on hub.pantacor.com or with:

```bash
pvr device get <device-nick>
```

## 5 — View Device Logs Remotely

Pantahub streams logs from the device to the cloud. Use `pvr device logs` to read them without SSH:

```bash
# All recent logs
pvr device logs my-device

# Filter by source — sources are log paths, e.g. /pantavisor.log for the
# Pantavisor runtime, or a container's console log
pvr device logs --source=/pantavisor.log my-device

# Filter by severity
pvr device logs -l ERROR my-device
```

## 6 — Device Metadata

Attach user-metadata key/values to devices to organize your fleet:

```bash
pvr device set <device-id> location=warehouse tier=production
pvr device get <device-nick>
```
