---
title: Local Network
sidebar_position: 3
description: Reach a Pantavisor device over the local network — SSH, the pvr CLI on port 12368, and the pvtx web UI.
---

Once the device has an IP address, you can reach it over SSH, interact with it via `pvr` from your workstation, and browse its pvtx web UI.

## Connect to a Network

**Ethernet**: Plug an Ethernet cable into the device and your router. The device obtains an IP via DHCP automatically.

**Wi-Fi**: Configure the wireless network from the serial console or by pre-configuring the network container before flashing.

## Find the Device IP

From the serial console debug shell:

```bash
ip addr show eth0
# or
ifconfig eth0
```

Look for the `inet` line — for example `inet 192.168.1.102/24`.

From your workstation, scan for Pantavisor devices on the local network:

```bash
pvr device scan
```

## SSH Access

SSH is served by the pvr-sdk container running on the device. Authentication is via your SSH public key — register it on the device first (see [Security](#security) below), then connect:

```bash
ssh root@<device-ip>
```

Once connected you have a shell inside the pvr-sdk container. From there you can reach the Pantavisor host commands via `pvcontrol`. `pventer` is not available inside pvr-sdk — to enter other containers, use the [serial debug shell](./serial-port.md) instead.

## pvr CLI Access

With the device's IP, your workstation can clone and manage the device state directly:

```bash
pvr clone http://<device-ip>:12368/cgi-bin my-device
```

Pantavisor exposes the revision management endpoint on port **12368**. All `pvr` operations — adding containers, deploying revisions — communicate through this port.

## pvtx Web UI

Open a browser to:

```
http://<device-ip>:12368/app
```

The pvtx UI shows the current revision state, running containers, logs, and device configuration. You can also upload container packages and commit transitions from here.

## Security

Use SSH public-key authentication. Writing `~/.ssh/authorized_keys` inside the container does not persist — the rootfs is a read-only squashfs and only `/etc/dropbear` is a volume. Instead, set the user-metadata key `pvr-sdk.authorized_keys`, either from the Pantahub UI or with the CLI:

```bash
pvr device set <device-id> pvr-sdk.authorized_keys="$(cat ~/.ssh/id_ed25519.pub)"
```

(From an existing session on the device you can also use `pvcontrol usrmeta save pvr-sdk.authorized_keys "<key>"`.)

Setting this key also enables the host dropbear server on port **8222**:

```bash
ssh -p 8222 <container>@<device-ip>   # shell inside a named container
ssh -p 8222 /@<device-ip>             # the Pantavisor console
```

Alternatively, bake the key into the image through the `_config/pvr-sdk/` overlay in your `pvr` checkout (see [Configure Applications](/meta-pantavisor/getting-started/develop/application/configure)).