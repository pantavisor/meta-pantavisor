---
title: Solutions
description: How Pantavisor solves recurring embedded Linux problems — firmware size, reproducible builds, secure OTA, and composable IoT gateways.
sidebar_position: 10
---

# Solutions

Each solution maps a common embedded Linux pain point to the concrete Pantavisor
mechanism that addresses it.

- **[Reduce firmware size](/meta-pantavisor/getting-started/solutions/firmware-size)** — Pantavisor itself is ~1 MB, no daemon, content-addressed dedup.
- **[Reproducible builds](/meta-pantavisor/getting-started/solutions/reproducible-builds)** — content-addressed state revisions are bit-exact.
- **[Secure OTA updates](/meta-pantavisor/getting-started/solutions/secure-ota)** — PVS signatures over the state JSON, x5c chains, audit trail.
- **[IoT gateway with composable containers](/meta-pantavisor/getting-started/solutions/iot-gateway)** — mix BSP, networking, VPN, and protocol adapters per product line.
