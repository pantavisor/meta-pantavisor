# MCU in Pantavisor State

## Overview

This document describes how MCU containers are declared in the Pantavisor
revision state and how they are mapped to physical hardware.

An MCU container, like any other container, declares what it is and what it
needs in `run.json` and what it exports in `services.json`. These files are
authored by the MCU container developer and are part of the revision state.

The decision of which physical MCU a container gets installed to is a
separate concern -- it is maintained by the **device integrator** in the BSP
container, specifically in `bsp/mcu.json`. This file is not part of any
individual container. It is part of the system definition and lives in the
BSP alongside the kernel and device tree. It carries the device integrator's
knowledge of the hardware: which MCU is connected to which UART, what its
name is, how it is wired, and what its constraints are -- for example the
maximum baudrate the UART connection supports, so Pantavisor can reject a
firmware deployment that requires a higher baudrate than the hardware allows.

This separation means MCU containers are hardware-agnostic. A container
named "drive-controller" can be deployed to any board that has an MCU mapped
to that name in its `bsp/mcu.json`, without the container itself knowing
anything about `/dev/ttyACM0` or GPIO pin numbers.

---

## Files Involved

```
Pantavisor revision state
├── trails/<rev>/
│   ├── <mcu-name>/
│   │   ├── run.json          <- MCU container declaration (transport, device,
│   │   │                        baudrate, service requirements)
│   │   └── services.json     <- what the MCU exports to Linux containers
│   └── ...
└── bsp/
    ├── kernel.itb
    ├── mcu/
    │   ├── <mcu-name>.elf    <- Zephyr / FreeRTOS firmware binary
    │   ├── <mcu-name>.ver    <- firmware version string
    │   └── <mcu-name>.sha256 <- integrity check
    └── mcu.json              <- BSP device mapping (abstract name -> tty/rpmsg)
```

---

## run.json -- MCU Container Declaration

Declares what the MCU container is, how to reach it, and what Linux services
it needs. Produced by the same build that produces the firmware ELF, so the
baudrate is always consistent.

```json
{
  "#spec": "service-manifest-run@1",
  "name": "drive-controller",
  "type": "mcu",

  "mcu": {
    "device": "drive-controller",
    "transport": "uart",
    "baudrate": 921600
  },

  "firmware": "bsp/mcu/drive-controller.elf",

  "policy": {
    "tryboot": {
      "health_timeout_s": 30,
      "on_failure": "rollback"
    },
    "operational": {
      "on_crash": "restart",
      "max_restarts": 3
    }
  },

  "services": {
    "required": [
      {
        "name": "system-bus",
        "type": "dbus",
        "interface": "org.freedesktop.NetworkManager",
        "target": "/run/dbus/system_bus_socket"
      },
      {
        "name": "iot-bridge",
        "type": "rest",
        "target": "/run/pv/services/iot.sock"
      }
    ]
  }
}
```

### device field -- abstract name or concrete path

```
"device": "drive-controller"   abstract name, resolved via bsp/mcu.json
"device": "/dev/ttyACM0"       concrete path, no bsp/mcu.json lookup needed
"device": "/dev/ttyRPMSG0"     RPMsg endpoint, transport must be "rpmsg"
```

Using abstract names is preferred. The BSP package builder knows which
physical device corresponds to which MCU function on their specific board.
The MCU container author should not need to know `/dev/ttyACM0` specifically.

### transport field

```
"transport": "uart"    UART connection (external MCU via tty device)
"transport": "rpmsg"   RPMsg (internal M core, e.g. i.MX8MN M7)
```

When transport is `rpmsg`, the baudrate field is ignored.

### baudrate field

The baudrate is a build-time constant -- it is set in the Zephyr Kconfig or
FreeRTOS build configuration and must match the firmware. Since run.json is
generated from the same build as the firmware ELF, they are always consistent.

```
Default: 921600
```

921600 works on all supported MCU platforms (RP2040, STM32, nRF52, ESP32)
and is fast enough for all PVCM message types including firmware updates.
Only change if the specific hardware cannot achieve 921600.

---

## services.json -- MCU Service Exports

Declares what the MCU firmware exports to Linux containers. Same format as
Linux container services.json per the xconnect specification.

```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    {
      "name": "mcu-sensor",
      "type": "dbus",
      "socket": "/run/pv/mcu/sensor.sock"
    },
    {
      "name": "mcu-display",
      "type": "rest",
      "socket": "/run/pv/mcu/display.sock"
    }
  ]
}
```

pvcm-manager registers these on the Linux system bus or as REST endpoints
so Linux containers can call into the MCU via the standard xconnect service
mesh.

---

## bsp/mcu.json -- BSP Device Mapping

Maps abstract MCU names to actual hardware devices on the specific board.
Owned and produced by the BSP package builder. Does not change between
revisions unless the hardware changes.

```json
{
  "#spec": "pvcm-bsp-map@1",
  "mcus": [
    {
      "name": "drive-controller",
      "device": "/dev/ttyACM0",
      "transport": "uart",
      "reset_gpio": 42
    },
    {
      "name": "display",
      "device": "/dev/rpmsg0",
      "transport": "rpmsg"
    },
    {
      "name": "sensors",
      "device": "/dev/ttyACM1",
      "transport": "uart",
      "reset_gpio": 43
    }
  ]
}
```

### reset_gpio field

GPIO number used by pvcm-manager to assert MCU reset during firmware update
and tryboot transitions. Required for external MCUs, not applicable for
RPMsg (remoteproc handles reset for internal M cores).

### Resolution in pvcm-manager

```c
const char *pvcm_resolve_device(const char *name,
                                 pvcm_transport_t **transport) {
    /* 1. already a concrete device path -- use directly */
    if (name[0] == '/') {
        *transport = pvcm_transport_for_path(name);
        return name;
    }

    /* 2. look up abstract name in bsp/mcu.json */
    bsp_mcu_map_t *map = pvcm_load_bsp_map("bsp/mcu.json");
    for (int i = 0; i < map->count; i++) {
        if (strcmp(map->mcus[i].name, name) == 0) {
            *transport = pvcm_transport_for_type(map->mcus[i].transport);
            return map->mcus[i].device;
        }
    }

    LOG_ERR("PVCM: no device mapping for '%s' in bsp/mcu.json", name);
    return NULL;
}
```

---

## Firmware ELF in BSP Container

The firmware ELF lives in the BSP container alongside the kernel. It is
optional -- if not present, pvcm-manager treats the MCU as not requiring
firmware installation (e.g. MCU has its own firmware already programmed).

```
bsp/mcu/<name>.elf      Zephyr or FreeRTOS ELF binary
bsp/mcu/<name>.ver      version string, e.g. "42" (matches revision)
bsp/mcu/<name>.sha256   SHA256 of ELF for integrity verification
```

pvcm-manager uses the `.ver` file to detect firmware version mismatch and
the `.sha256` file to verify integrity before flashing.

---

## Who Produces What

```
Device integrator (BSP owner):
  bsp/mcu.json              hardware mapping for this specific board --
                            MCU names, tty/rpmsg devices, wiring constraints
                            (max baudrate, reset GPIO)
                            lives in BSP container, not in any MCU container
                            stable across revisions unless hardware changes

MCU firmware / BSP build:
  bsp/mcu/<n>.elf           firmware binary (from Zephyr/FreeRTOS build)
  bsp/mcu/<n>.ver           version string
  bsp/mcu/<n>.sha256        integrity hash

MCU container developer:
  <n>/run.json              abstract device name, transport, baudrate,
                            service requirements
                            hardware-agnostic -- no tty paths, no GPIOs
  <n>/services.json         what the MCU exports back to Linux containers

Yocto build (automated):
  baudrate in run.json      generated from same Kconfig as firmware ELF
                            cannot diverge -- same build produces both
```
---

## Multiple MCU Containers -- Full Example

A product with an internal M7 (display) and two external MCUs (motor, sensors):

**bsp/mcu.json** (BSP builder, board-specific):
```json
{
  "#spec": "pvcm-bsp-map@1",
  "mcus": [
    { "name": "display",    "device": "/dev/rpmsg0",  "transport": "rpmsg" },
    { "name": "motor",      "device": "/dev/ttyACM0", "transport": "uart",
      "reset_gpio": 42 },
    { "name": "sensors",    "device": "/dev/ttyACM1", "transport": "uart",
      "reset_gpio": 43 }
  ]
}
```

**display/run.json** (internal M7, RPMsg, no baudrate):
```json
{
  "#spec": "service-manifest-run@1",
  "name": "display",
  "type": "mcu",
  "mcu": { "device": "display", "transport": "rpmsg" },
  "firmware": "bsp/mcu/display.elf",
  "services": {
    "required": [
      { "name": "system-bus", "type": "dbus",
        "interface": "org.freedesktop.NetworkManager",
        "target": "/run/dbus/system_bus_socket" }
    ]
  }
}
```

**motor/run.json** (external MCU, UART 921600):
```json
{
  "#spec": "service-manifest-run@1",
  "name": "motor",
  "type": "mcu",
  "mcu": { "device": "motor", "transport": "uart", "baudrate": 921600 },
  "firmware": "bsp/mcu/motor.elf",
  "services": {
    "required": [
      { "name": "iot-bridge", "type": "rest",
        "target": "/run/pv/services/iot.sock" }
    ]
  }
}
```

**motor/services.json** (MCU exports motor status to Linux):
```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    { "name": "motor-status", "type": "rest",
      "socket": "/run/pv/mcu/motor.sock" }
  ]
}
```

**sensors/run.json** (external MCU, UART 460800 -- different baudrate):
```json
{
  "#spec": "service-manifest-run@1",
  "name": "sensors",
  "type": "mcu",
  "mcu": { "device": "sensors", "transport": "uart", "baudrate": 460800 },
  "firmware": "bsp/mcu/sensors.elf"
}
```

**sensors/services.json** (MCU exports sensor data to Linux):
```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    { "name": "sensor-data", "type": "dbus",
      "socket": "/run/pv/mcu/sensors.sock" }
  ]
}
```

---

## Prototype Setup -- RP2040 Pico via USB

For development with RP2040 Picos connected via USB, the bsp/mcu.json uses
the ttyACM device names that appear when Picos are plugged in:

```json
{
  "#spec": "pvcm-bsp-map@1",
  "mcus": [
    { "name": "display",    "device": "/dev/ttyACM0", "transport": "uart",
      "reset_gpio": null },
    { "name": "motor",      "device": "/dev/ttyACM1", "transport": "uart",
      "reset_gpio": null },
    { "name": "sensors",    "device": "/dev/ttyACM2", "transport": "uart",
      "reset_gpio": null },
    { "name": "io",         "device": "/dev/ttyACM3", "transport": "uart",
      "reset_gpio": null }
  ]
}
```

`reset_gpio: null` means pvcm-manager cannot assert hardware reset. Firmware
update still works via the PVCM firmware update protocol -- the MCU reboots
itself after receiving a complete firmware image. For RP2040 the UF2
bootloader path is also available if needed.

The run.json files for the MCU containers are identical between prototype
and production. Only bsp/mcu.json changes when moving from ttyACM (USB) to
hardware UART or RPMsg.
