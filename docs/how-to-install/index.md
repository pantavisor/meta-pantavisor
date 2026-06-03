---
title: "How to Install"
description: "Flash and install Pantavisor images on hardware and local targets."
sidebar_position: 3
---

# How to Install

Guides for getting a Pantavisor image onto a device, from SD card flashing to board-specific install methods.

## Topics

1. [SD Card](sdcard.md) — write a `.wic` image to an SD card using `pvflasher` or `dd`; the generic method for most boards
2. [Docker / Local Target](docker.md) — run Pantavisor locally with Docker for development and testing without hardware
3. [Tezi](tezi.md) — install using Toradex Easy Installer for Toradex Colibri and Verdin modules
4. [UUU](uuu.md) — flash NXP i.MX targets using the Universal Update Utility
5. [Board Guides](boards/) — board-specific wiring, boot-mode selection, and install notes

## Choose Your Method

| Target | Method |
|--------|--------|
| Most boards (SD card slot) | [SD Card](sdcard.md) |
| Toradex Colibri / Verdin | [Tezi](tezi.md) |
| NXP i.MX EVK / SOM | [UUU](uuu.md) |
| Local development | [Docker](docker.md) |
