---
title: IoT gateway with composable containers
sidebar_position: 4
description: Build composable IoT gateways with Pantavisor — BSP, networking, VPN, protocol adapters, and edge processing, each as an independent LXC container, updated independently with atomic OTA.
---

# IoT gateway with composable containers

## What an IoT gateway needs

A typical IoT or industrial gateway sits at the boundary between field-side
equipment (sensors, PLCs, machines) and the cloud. It needs:

- a **stable BSP** for the chosen hardware (RPi, NXP, TI, etc.),
- **networking** (Ethernet, Wi-Fi, LTE, sometimes LoRa),
- **secure remote access** (VPN, mesh networking),
- **protocol adapters** (Modbus, OPC-UA, CAN, BACnet, custom serial),
- a **local broker / buffer** (MQTT, store-and-forward),
- **edge processing** (filtering, aggregation, anomaly detection),
- **OTA updates** for every layer above,
- **auditable, recoverable updates** for compliance and uptime.

Building this as a monolithic image means every change to one piece reflashes the
whole device. Composable containers fix that.

## Pantavisor's gateway composition

Each gateway is a state composed of independent containers:

```
my-iot-gateway/ (state JSON)
├── bsp/              # Kernel, modules, firmware (e.g. RPi 4 ARMv8)
├── os/              # Alpine + ConnMan (networking)
├── tailscale/        # Mesh VPN container
├── modbus/           # Industrial protocol adapter
├── mqtt-broker/      # Local MQTT broker (Mosquitto)
├── edge-app/         # Custom edge processing
└── pvr-sdk/          # Optional management container (dev/diagnostics)
```

Each container is built and versioned independently, has its own `run.json` and
`_config/<container>/` overlays, reaches the services of other containers through
[pv-xconnect](/meta-pantavisor/getting-started/develop/application/access-applications) inter-container
networking (startup ordering comes from container groups/runlevels), and has its
own `status_goal` so failures are caught and rolled back automatically.

## Why composability matters here

- **Different teams, different cadences.** The kernel team ships a quarterly BSP
  update; the networking team patches ConnMan when a CVE drops; the edge-app team
  ships weekly. With monolithic firmware every cadence collides. With containers,
  each team owns its piece and ships independently.
- **Different SKUs, shared base.** A "Wi-Fi-only" and a "Wi-Fi + LTE" gateway can
  share BSP, OS, MQTT, and edge-app, differing only in the modem container. No
  fork, no parallel build pipelines.
- **Per-customer customization.** Customer A wants Modbus + S3 export; customer B
  wants OPC-UA + Azure IoT Hub. Two custom containers per customer, everything
  else shared.

## Building one — concrete example

Using the Yocto path (see [Build with Yocto](/meta-pantavisor/overview/get-started)), compose the initial image
from container recipes:

```bitbake
SUMMARY = "Industrial IoT Gateway"
LICENSE = "MIT"

inherit image pvroot-image

PVROOT_CONTAINERS_CORE ?= "\
    pv-alpine-connman   \
    pv-tailscale        \
    pv-mqtt-broker      \
    edge-app            \
"

# Optional, installed per-customer on first boot
PVROOT_CONTAINERS ?= "\
    modbus-adapter      \
    opcua-adapter       \
"

PVROOT_IMAGE_BSP ?= "core-image-minimal"
```

Build, flash, and boot — the gateway comes up with all core services running.
Optional containers are factory-bundled and installed on first boot per device
metadata.

## Failure isolation

A crashing `edge-app` container restarts (per its `restart_policy`) without
affecting the MQTT broker, Tailscale, or the BSP. A failed update to the Modbus
container rolls back without touching the rest of the composition. This is the
practical difference between "containers" and "monolith": one bad component
doesn't take down the whole gateway.

## OTA per container

```bash
# Update only the protocol adapter
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME ws
cd ws
pvr app update modbus --from gitlab.com/myorg/modbus-adapter:1.4.2
pvr sig add --part modbus
pvr add .
pvr commit -m "Modbus 1.4.2 — fix register decode"
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

Other containers are untouched. Differential transfer ships only the changed
object hashes — minutes over cellular instead of a full reflash.

## Hardware targets

Gateway hardware that runs Pantavisor today includes Raspberry Pi 3/4/5 (see
[supported devices](/meta-pantavisor/overview/supported-device)), custom ARM64/ARMv7 boards via
your own `MACHINE` definition + [meta-pantavisor](/meta-pantavisor/overview/get-started), and x86 industrial PCs.

## Next steps

- [Develop applications](/meta-pantavisor/getting-started/develop) — build and ship the gateway's containers
- [Operate devices](/meta-pantavisor/getting-started/operate) — fleet-wide staged rollouts
- [Secure OTA updates](/meta-pantavisor/getting-started/solutions/secure-ota) — sign every gateway update
