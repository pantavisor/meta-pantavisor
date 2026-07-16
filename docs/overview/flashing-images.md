---
title: "Flashing Images"
sidebar_position: 7
description: "The ways to get a Pantavisor image onto a device: pre-built downloads, pvflasher, SD card, and NXP UUU-based factory flashing."
---

# Flashing Images

meta-pantavisor produces a bootable image for every supported machine. This
page is a map of how to get that image onto real hardware — where to get a
ready-made image, which tool to flash it with, and which method applies to
your board.

## What a Yocto build produces

A KAS/Yocto build of `pantavisor-starter` (see [Starter Image](images.md))
outputs two different kinds of artifact in
`build/tmp-${codename}/deploy/images/${machine}/`, and each is consumed
differently:

- **`.wic`** (plus its compressed variants `.wic.bz2` / `.wic.gz` / `.wic.zst`)
  — a complete, flashable **disk image**: partition table, bootloader, and a
  rootfs with an initial signed Pantavisor trail already populated. This is
  what you write to a device's storage (SD card, eMMC, NAND) the *first*
  time, before it can boot Pantavisor at all. **This page is about that
  step.**
- **`.pvrexport.tgz`** (a **pvrexport**) — a tarball of one state part (an
  app container or the BSP), built per-recipe and mixed into the `.wic`'s
  initial trail at image-build time (see
  [Build artifacts](images.md#build-artifacts) and
  [How the image is assembled](images.md#how-the-image-is-assembled)). The same
  pvrexports are what Pantavisor deploys **after** first boot: `pvtx`, the
  device web UI, or `pvr` can post a new pvrexport to an already-running
  device, and Pantavisor commits it as a new trail revision — this is how
  **OTA updates** work, with no reflashing involved.

In short: `.wic` gets a device booting Pantavisor for the first time;
`.pvrexport` tarballs are how every update reaches it afterward. The rest of
this page covers the `.wic` side — initial flashing.

## Get an image: pantavisor.io/downloads

[pantavisor.io/downloads](https://pantavisor.io/downloads/) is the fastest way
to get a Pantavisor image without building one yourself. It lists official
release channels (stable, release-candidate) and versions for all supported
boards, ready to flash.

The downloads page also distributes
[**pvflasher**](https://pantavisor.io/downloads/#:~:text=pvflasher,GUI%20and%20CLI),
Pantacor's open-source flashing tool (GUI and CLI, Linux/Windows/macOS). Its
GUI includes an integrated release browser — pick a channel, version, and
device profile, then download and flash in one step, without leaving the app.

## Choose your flashing method

| Target | Method | Guide |
|--------|--------|-------|
| Most boards (SD card slot) | Write a `.wic` image with **pvflasher** or `dd` | [SD Card](../getting-started/how-to-install/sdcard.md) |
| Toradex Colibri / Verdin | UUU + `pv-flash-bundle` (factory flash, no host `uuu` install) | [Flashing Toradex Modules](../getting-started/how-to-install/toradex.md) |
| NXP i.MX EVK / SOM (Variscite, MEK) | UUU + `pv-flash-bundle` | [Flashing via NXP uuu](../getting-started/how-to-install/uuu.md) |
| Local development, no hardware | Docker | [Docker / Local Target](../getting-started/how-to-install/docker.md) |

Board-specific wiring, boot-mode switches, and install notes for each
supported board live under [Board Guides](../getting-started/how-to-install/boards/index.md).

For the NXP i.MX boards (Toradex and Variscite), `pv-flash-bundle` is the
preferred flashing method — see
[Flashing NXP devices](pv-flash-bundle.md) for how the recipe assembles the
self-contained factory-flash archive.

## Verifying a flash

`pvflasher verify` re-checks a flashed SD card against the image's block map
(`.bmap`) without re-flashing — useful for confirming a card before shipping
a device. See [SD Card](../getting-started/how-to-install/sdcard.md) for
the full pvflasher CLI/GUI walkthrough.
