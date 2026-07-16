---
title: Raspberry Pi
sidebar_position: 0
description: Install Pantavisor on a Raspberry Pi — machine names, pre-built CI images, SD card flashing, serial console, and A/B boot with tryboot.
---

# Raspberry Pi

The Raspberry Pi is the easiest way to evaluate Pantavisor: pre-built images
are published for every release and the board boots straight from an SD card —
no recovery mode, jumpers, or vendor flashing tools.

## Machines

| Machine | Covers | Pre-built images |
|---------|--------|------------------|
| `raspberrypi-armv8` | Raspberry Pi 3 / 4 (64-bit) | Yes (CI-built) |
| `rpi` | All Raspberry Pi variants, including RPi 5 — multi-kernel config that bundles a kernel per SoC | Yes (CI-built) |
| `raspberrypi-armv7` | 32-bit builds for older boards | Build locally |

If unsure, pick **`raspberrypi-armv8`** for a Pi 3 or 4.

## Install

The Raspberry Pi flashes like any SD-card board:

1. Download the `pantavisor-starter-<machine>*.wic.bz2` image — or let
   `pvflasher install` pick a release interactively.
2. Flash it with `pvflasher copy <image> /dev/sdX`.

The [download and flash quickstart](/meta-pantavisor/getting-started/start/download-and-flash) walks through
the whole flow step by step; the [SD card guide](../sdcard.md) covers the
flashing tools in more detail.

## A/B boot

Raspberry Pi images use the firmware's **tryboot** mechanism
(`PV_BOOTLOADER_TYPE=rpiab`) for atomic A/B boot-partition updates with
automatic fallback. See the [build system overview](/meta-pantavisor/overview/build-system) for
how the `rpi-tryboot` images are assembled.

## Serial console

Connect a USB-to-TTL adapter to the GPIO header: GPIO14 (TX) → adapter RX,
GPIO15 (RX) → adapter TX, GND → GND, at **115200 8N1**. See
[serial port access](/meta-pantavisor/getting-started/operate/device-access/serial-port) for using the debug
shell.

## Next steps

- [Access the device](/meta-pantavisor/getting-started/operate/device-access) over serial or the local network
- [Install your first application](/meta-pantavisor/getting-started/develop/application/install/)
