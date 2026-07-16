---
title: Device Access
sidebar_position: 10
description: Ways to access a Pantavisor device — serial console, SSH over the local network, the pvtx web UI, and remote management through Pantahub.
---

A Pantavisor device exposes several access points depending on your connectivity and what you need to do.

| Method | When to use |
|--------|-------------|
| [Serial console](./serial-port/) | First boot, network not yet configured, low-level debugging, debug shell |
| [Local network — SSH](./local-network/) | Day-to-day management once the device is on a network |
| [pvtx web UI](./pvtx-ui/) | Browse container status, view logs, upload container packages without the CLI |
| [Pantahub — remote](./remote-pantahub/) | OTA updates, log streaming, and device management from anywhere |

### Serial Console

The serial console is the lowest-level access path and works without any network configuration. Pantavisor prints a debug shell prompt shortly after boot — pressing **Enter** drops you into a root shell where you can run `lxc-ls`, `pventer`, and `pvcontrol` directly on the device. Note that the prompt varies by Pantavisor version and configuration — older images show "Press [d] for debug ash shell" instead.

### Local Network

Once the device has an IP address (via Ethernet or Wi-Fi), you can reach it over SSH and via `pvr` on your workstation. The `pvr` CLI clones the device state, lets you add or modify containers, and deploys the new revision back over the network. The pvtx web UI on port **12368** is served by the pvr-sdk container; on images that bind it to localhost only, expose it with a `_config/pvr-sdk/etc/pvr-sdk/config.json` overlay setting `"listen": "0.0.0.0"`.

### Pantahub

Devices that are claimed on [Pantahub](https://hub.pantacor.com) can be managed from anywhere. The `pvr` CLI authenticates to Pantahub and lets you clone, modify, and push device state remotely — the device polls for updates and applies them as OTA revisions. Logs are streamed to Pantahub in real time.