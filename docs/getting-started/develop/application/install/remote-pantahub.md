---
title: Install remotely via Pantahub
sidebar_position: 43
description: Install an application on a Pantavisor device remotely through Pantahub — claim the device, upload a container package, and commit the transaction from the cloud dashboard.
---

Pantahub is the cloud backend for Pantavisor. Once a device is claimed, you can push application updates to it from anywhere — the device polls Pantahub and applies the new revision automatically.

---

## 1 — Claim Your Device

Before remote management is possible, the device must be registered in your Pantahub account. The device prints a one-time challenge token and its device ID on boot.

Read them from the device console (serial or SSH):

```bash
cat /pv/challenge
# pleasantly-finer-unicorn

cat /pv/device-id
# 5b582638c67920b9de2
```

Log in to [hub.pantacor.com](https://hub.pantacor.com), go to **Claim Device**, and enter the device ID and challenge. Once claimed, the device appears in your device list and its status updates in real time.

See [Remote access via Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) for the canonical claiming and remote-access walkthrough.

---

## 2 — Build the Container Package

On your workstation, build the container you want to install using `pvr`. If you have not done this yet, follow the steps in the [pvtx install guide](./local-pvtx.md) to create a `myapp.tar.gz` bundle.

---

## 3 — Deploy via Pantahub

From the device dashboard on hub.pantacor.com:

1. Click the device name to open its detail view.
2. Go to the **Manage** tab.
3. Click **Begin Transaction**.
4. Click **Upload New Part** and select your `myapp.tar.gz` file.
5. Enter a commit message and click **Commit Transaction**.

Pantahub queues the update. The device polls for new revisions periodically and downloads the changed container objects as a diff (only the objects that changed are transferred). It then applies the new revision.

### Or via the pvr CLI

You can also push the revision from your workstation instead of the dashboard: `pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME`, make your changes, then `pvr add .`, `pvr commit` and `pvr post`. See [Remote access via Pantahub](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) for the full remote workflow.

---

## 4 — Monitor the Update

The device dashboard shows the update progress in real time:

| Status | Meaning |
|--------|---------|
| `QUEUED` | Update queued, waiting for the device to pick it up |
| `DOWNLOADING` | Device is downloading the changed objects |
| `INPROGRESS` | Device is installing and transitioning into the new revision |
| `TESTING` | Device is running the new revision, performing stability checks |
| `DONE` | Revision committed — update successful |
| `ERROR` / `WONTGO` | Update failed — the device stays on (or rolls back to) the last good revision |

If the status reaches `DONE`, the new container is running. If it ends in `ERROR` or `WONTGO`, Pantavisor keeps the device on the previous good revision — no manual intervention needed.

---

## Next Steps

- [View running applications](/meta-pantavisor/getting-started/develop/application/view) — check container status and logs on the device
- [Configure applications](/meta-pantavisor/getting-started/develop/application/configure) — push configuration changes through the same revision workflow