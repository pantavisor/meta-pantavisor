---
title: Start
description: Get Pantavisor running — flash a Raspberry Pi in about 30 minutes, or try it in Docker with no hardware.
sidebar_position: 2
---

# Start

The fastest way to understand Pantavisor is to run it — flash a real device,
boot it, and ship your first update.

## Paths

- **[Download and flash on a Raspberry Pi](./download-and-flash.md)** — flash a
  pre-built starter image and boot real hardware in about 30 minutes. No
  Yocto or container background needed for this path.
- **No hardware?** [Run Pantavisor in Docker (AppEngine)](/meta-pantavisor/getting-started/how-to-install/docker) on
  your workstation — see the [glossary](../../overview/glossary.md#appengine)
  for what "AppEngine" means here (not a PaaS). Note: there's no pre-built
  AppEngine image to download, so this path still needs the Yocto/BitBake
  toolchain to build one — it's a no-*hardware* alternative, not a
  no-*build* one.
- **Install `pvr`** — the client used to inspect and change [device state](../../overview/glossary.md#state-state-json). Every
  change is an explicit, one-shot `pvr post` — there's no background agent
  continuously reconciling drift the way a Kubernetes controller would. See
  the [`pvr` installation guide](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli#installation).

## Prerequisites

- A Raspberry Pi 3B/3B+/4 with a microSD card (8 GB or more), or Docker for the
  no-hardware path.
- A laptop or desktop to download and flash the image.
- Optional but recommended: a USB-to-TTL serial adapter for console access —
  check its logic-level voltage matches the board (see [Serial Console](/meta-pantavisor/getting-started/operate/device-access/serial-port)).

## Next steps

- [Install your first application](/meta-pantavisor/getting-started/develop/application/install/) with `pvr`.
- [Access your device](/meta-pantavisor/getting-started/operate/device-access) over serial, the local network,
  or [Pantahub](../../overview/glossary.md#pantahub).

> **📝 Note**
>
> Pantavisor manages the entire device update itself. There is no separate A/B
> image updater to install or configure underneath it.
