# Pantavisor MCU Containers

## The fourth container type. The one that was always missing.

---

## Who This Is For

Pantavisor MCU addresses three groups of people building embedded products
that combine Linux with real-time firmware:

**You have a Linux SoC with an internal M core you are not using.**
i.MX8MN, i.MX8MP, i.MX8QM -- all ship with one or two Cortex-M cores
sitting dormant on the die. You are not using them because wiring up
remoteproc, RPMsg, firmware loading, OTA coupling, and health monitoring
is a significant engineering investment for uncertain gain. Pantavisor MCU
makes it trivial. The M core becomes a container. Everything else follows.

**You already have an external MCU connected to Linux.**
Your product has a Cortex-M next to your application processor, connected
via UART or SPI. You wrote a custom protocol. It works. But every project
reinvents this wheel. There is no OTA story for the MCU firmware. A bad
firmware update has no rollback. The MCU and Linux can get out of sync.
Pantavisor MCU gives your existing setup the same atomic revision model
you already use for Linux containers.

**You are designing a new product and want to do it right from the start.**
You want the MCU to be a real-time frontend for a Linux backend, with
proper OTA, health monitoring, service mesh integration, and log visibility
-- without building all of that yourself. Pantavisor MCU is that foundation.
Prototype with dev boards you already own. Ship on production silicon.
The same revision model throughout.

---

## What Pantavisor MCU Is

Alongside LXC, runc, and Wasm, Pantavisor now supports a fourth container
type: the MCU.

```
Pantavisor container types

  LXC    Linux processes, full userspace
  runc   OCI containers, Docker-compatible
  Wasm   WebAssembly, portable sandboxed modules
  MCU    real-time firmware, any RTOS or bare metal    <- new
```

An MCU container is a Zephyr or FreeRTOS firmware artifact in the
Pantavisor revision. It has the same properties as every other container:
it is versioned, deployed, health-checked, and rolled back atomically
alongside the Linux containers. The MCU is just another peer in the
revision -- managed with the same mental model, the same tooling, and the
same operational workflow you already use.

One platform. Every compute paradigm.

---

## The Container Mindset Applied to MCU

The value of treating the MCU as a container is not primarily about new
capabilities -- it is about applying a model that already works to a domain
that has historically been outside it.

**Revision coupling.**
Today, if you roll back a Linux revision, the MCU firmware does not roll
back with it. They can diverge. A bad MCU firmware update has no automatic
recovery. With Pantavisor MCU, the MCU firmware is part of the revision.
Roll back the revision and everything rolls back -- Linux containers and
MCU firmware together, atomically.

**Health-checked commits.**
Pantavisor already gates Linux revision commits on container health checks.
MCU containers participate in the same gate. If the MCU firmware is
unhealthy after an OTA update -- crash loops, missing heartbeats, explicit
health failure -- the revision does not commit. The system rolls back before
anyone notices something went wrong.

**Bidirectional safety.**
Either side can trigger a rollback. Linux containers failing causes MCU
rollback. MCU firmware crashing repeatedly causes Linux rollback. The system
is consistent by design, not by careful manual coordination.

**Unified observability.**
MCU log output flows into the Pantavisor log infrastructure alongside
container logs -- timestamped, tagged, forwarded to cloud. The same query
that shows your container logs shows your MCU firmware logs. Production
visibility for MCU firmware with zero infrastructure work.

**Zero-config onboarding.**
Add an MCU container to any existing revision. pvcm-manager detects a
virgin MCU, installs firmware, migrates boot state automatically. No factory
re-flash. No special tooling. The MCU joins the revision model on first boot.

---

## The Service Mesh -- The MCU as a First-Class Peer

Once the MCU is in the Pantavisor revision, it joins the existing
pv-xconnect service mesh. The same mechanism Linux containers use to declare
services and consume them -- `services.json` and `run.json` -- works for
MCU containers too.

An MCU container declares what Linux services it needs:

```json
{
  "services": {
    "required": [
      { "name": "system-bus", "type": "dbus",
        "interface": "org.freedesktop.NetworkManager",
        "target": "/run/dbus/system_bus_socket" },
      { "name": "iot-bridge", "type": "rest",
        "target": "/run/pv/services/iot.sock" }
    ]
  }
}
```

And declares what it exports back to Linux:

```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    { "name": "mcu-sensor", "type": "rest",
      "socket": "/run/pv/mcu/sensor.sock" }
  ]
}
```

pv-xconnect reads the xconnect-graph, finds the MCU consumer connections,
and pvcm-manager sets up the corresponding RPMsg or UART bridge routes.
The MCU is wired into the service mesh the same way every other container is.

```
xconnect-graph -- the complete system topology:

  network-bridge  --[dbus]-->  my-linux-app      socket injected into ns
  network-bridge  --[dbus]-->  mcu-frontend      bridged via RPMsg/UART
  mcu-frontend    --[rest]-->  telemetry-app     MCU sensor data to Linux
```

One query to `/xconnect-graph` shows the complete connection topology
including every MCU service and consumer. The entire system is visible in
one place.

---

## What the MCU Gains From the Service Bed

Being in the mesh is not just about deployment safety. The MCU firmware now
has access to everything Linux containers provide -- without any of it living
in the firmware.

**This is the simplest firmware that ever delivered this much.**

The MCU developer keeps the firmware focused on what an MCU is good at:
deterministic timing, direct hardware interaction, immediate response. All
the complexity that would compromise that -- network stacks, cloud SDKs,
TLS, certificate management, protocol libraries -- lives in Linux containers
and is reachable via a single function call.

### DBus -- The Most Trivial Way That Exists for RTOS Firmware

DBus is how Linux system services expose their capabilities: NetworkManager
controls WiFi, BlueZ controls Bluetooth, ModemManager controls cellular,
PipeWire controls audio. Accessing these from bare metal has always required
implementing the full DBus wire protocol, SASL authentication, and Unix
socket management. Nobody does it. It is too hard.

**Pantavisor MCU is the most trivial way to interface with DBus backend
services for MCUs that exists for RTOS firmware.**

Two tiers. Pick based on how much you want to know about the service:

**Tier 1 -- DBus message assembly (~6KB flash, ~1KB RAM)**
The SDK handles Unix sockets, SASL, framing, connection management. The
developer assembles typed DBus messages with simple helpers:

```c
pvcm_dbus_msg_t *msg = pvcm_dbus_call_new(
    "org.freedesktop.NetworkManager",
    "/org/freedesktop/NetworkManager",
    "org.freedesktop.NetworkManager",
    "AddAndActivateConnection"
);
/* append typed connection settings */
pvcm_dbus_send(msg, on_connected, NULL);

/* subscribe to state changes as a firmware callback */
pvcm_dbus_subscribe(
    "org.freedesktop.NetworkManager", NULL,
    "org.freedesktop.NetworkManager", "StateChanged",
    on_state_changed, NULL
);
```

**Tier 2 -- REST wrapper containers**
Companion containers wrap system services behind clean REST endpoints.
No DBus knowledge required anywhere in the firmware:

```c
pvcm_post("/network/connect",
          "{\"ssid\": \"Corp\", \"psk\": \"secret\"}",
          on_connected);

pvcm_post("/bluetooth/pair",
          "{\"address\": \"AA:BB:CC:DD:EE:FF\"}",
          on_paired);
```

The catalog includes containers for NetworkManager, BlueZ, ModemManager,
and PipeWire -- open source, OTA-updatable independently of firmware.

### The MCU Also Provides Services Back to Linux

The MCU is not just a consumer. It registers its own DBus service endpoints
that any Linux container can call:

```c
pvcm_dbus_expose(
    "/com/pantavisor/mcu/sensor/temperature",
    "com.pantavisor.mcu.Sensor", "GetTemperature",
    on_temp_request, NULL
);
```

```python
# Any Linux container reads the live MCU sensor
mcu = dbus.Interface(bus.get_object("com.pantavisor.mcu", "/..."), "...")
unit, value = mcu.GetTemperature()
```

### What the Firmware Developer Gets

Declared in `run.json`. Called with one function. Handled by Linux.

```
/network     WiFi scan, connect, state events    NetworkManager
/bluetooth   BLE scan, pair, connect, events     BlueZ
/modem       SMS, GPS, signal, data              ModemManager
/audio       Volume, routing, sources            PipeWire
/iot         Cloud telemetry, commands           custom container
/ai          ML inference, NLP, vision           custom container
/db          Query, store, time-series           custom container
/logs        Persistent log stream, cloud fwd    Pantavisor log server
/system      systemd health, journal             DBus
```

None of this complexity lives in the firmware. None of it ever needs to.

### Unified Logging

```kconfig
CONFIG_PANTAVISOR_LOG_BACKEND=y
```

That is all. Every `LOG_INF()`, `LOG_WRN()`, `LOG_ERR()` in the Zephyr
firmware flows into the Pantavisor log server alongside container logs --
timestamped, tagged by MCU container name, forwarded to the same cloud
destination as everything else. Production observability for MCU firmware
from the first boot, without a debug UART dangling out of the device.

---

## The RTOS SDK

```
Zephyr       SDK available    modern, growing fast, NXP-backed
FreeRTOS     SDK available    largest installed base, AWS-backed
ThreadX      SDK coming       industrial and medical, Azure RTOS
bare metal   protocol spec    any firmware that can talk UART
```

`CONFIG_PANTAVISOR=y`. The server, heartbeat, and service mesh client start
automatically. The developer writes application code. Nothing else required.

---

## MCU Comfy Mode -- Prototype With Dev Boards You Already Have

For teams designing new products, you do not need custom hardware to start.
Plug in the MCU dev boards you already own. Each becomes an MCU container
in your Pantavisor revision. This is MCU comfy mode -- a rich Linux service
bed with as many MCUs as you need, all in the revision model from day one.

### Recommended Dev Boards

**RP2040 Pico -- the best starting point**
$4. Plug into USB. Appears as `/dev/ttyACM0` immediately. No drivers, no
configuration. Firmware flashing is drag-and-drop via USB mass storage.
The PIO subsystem provides up to 4 additional software UARTs on any GPIO
pins with zero CPU overhead -- the PVCM transport never competes with
application peripherals or the debug UART.

**STM32 Nucleo -- for STM32 target development**
USART2 goes to the ST-Link virtual COM port. USART1 and USART3 are free
on the Arduino-compatible headers -- configure in STM32CubeIDE with a few
clicks. No software UART needed.

**Variscite i.MX8MN EVK -- zero wires**
The M7 is already inside the SoC. Enable RPMsg in the device tree. No extra
hardware. No wires. The best development experience.

### Multiple MCUs, One Revision

Nothing stops you from running four MCU containers simultaneously:

```
Linux SBC
  |-- /dev/ttyACM0  ->  Pico 0: display controller
  |-- /dev/ttyACM1  ->  Pico 1: motor controller
  |-- /dev/ttyACM2  ->  Pico 2: sensor fusion
  +-- /dev/ttyACM3  ->  Pico 3: IO expander
```

All four revision-coupled. All four health-monitored. All four OTA-updated
atomically alongside Linux containers. All four log output in the Pantavisor
log server. Linux brokers every connection between them via the service mesh.
No direct MCU-to-MCU protocol needed.

### From Prototype to Production

```
Prototype (comfy mode)           Production
──────────────────────           ──────────────────────────────
4x RP2040 Pico via USB           i.MX8QM dual M4 + external MCUs
$4 each, plug in                 single SoC, RPMsg transport
same Zephyr firmware             same Zephyr firmware
same services.json / run.json    same services.json / run.json
same Pantavisor revision         same Pantavisor revision
```

Transport changes. Hardware consolidates. Everything else stays identical.

---

## Use Cases

### Unlocking the Dormant M Core
Your i.MX8MN design has an M7 core you have never enabled. Add an MCU
container to your next revision. pvcm-manager loads the firmware via
remoteproc, migrates boot state, starts health monitoring. The M7 is now
a first-class part of your product -- instant-on display frontend, real-time
sensor fusion, or dedicated motor controller -- with full OTA safety and
log visibility from the first deployment.

### Replacing the Custom Serial Protocol
You have a working MCU+Linux product with a hand-rolled UART protocol. It
works but every new project reinvents it. Adopt the PVCM SDK on the MCU
side and pvcm-manager on Linux. Your existing UART connection becomes an
xconnect transport. The MCU joins the service mesh. The custom protocol
disappears. OTA rollback safety appears.

### Industrial Machine With Multiple Real-Time Domains
Safety relay controller, stepper motor driver, sensor array, operator panel
-- four separate MCU containers on four Picos, each doing one thing well.
Linux runs the PLC logic, SCADA connectivity, and OTA management. The service
mesh connects everything. One revision update covers all four MCUs and all
Linux containers simultaneously.

### New Product From Scratch
Design with an MCU alongside your application processor. Use the Pantavisor
RTOS SDK as the firmware foundation. Your MCU firmware declares what Linux
services it needs, exports its hardware capabilities, and receives logs,
health monitoring, and OTA for free. Spend engineering time on the product,
not the infrastructure.

---

## Developer Experience

### One Line in Your Yocto Config

```yaml
includes:
  - repo: meta-pantavisor
    file: kas/snippets/pvcm-mcu.yml

local_conf_fragment: |
  MCU_ZEPHYR_BOARD = "imx8mn_evk/mimx8mn6/m7"
  MCU_ZEPHYR_APP   = "path/to/your/app"
```

### Two Lines in Your Firmware Config

```kconfig
CONFIG_PANTAVISOR=y
CONFIG_PANTAVISOR_TRANSPORT_RPMSG=y   # or UART for external MCU
```

### One View in Pantahub

Every MCU alongside every container -- health, restarts, firmware version,
revision coupling, log stream. Query `/xconnect-graph` for the complete
service topology. One device. One revision. One operational view.

---

## Supported Hardware

| Platform | MCU | Transport | Notes |
|---|---|---|---|
| i.MX8MN / i.MX8MP | Internal M7 | RPMsg | Zero wires, best DX |
| i.MX8QM | Dual internal M4 | RPMsg x2 | Two RTOS domains |
| Any SoC + RP2040 Pico | External via USB | UART ttyACM | $4, plug in |
| Any SoC + STM32 Nucleo | External via header | UART | Free header UART |
| Any SoC + nRF52 DK | External via header | UART | + BLE |
| Any SoC | None | -- | Default backend, unchanged |

---

## Marketing Blurbs

### One-liner
> Pantavisor MCU is the fourth container type -- real-time firmware managed
> atomically alongside Linux containers, with OTA rollback, health checks,
> service mesh integration, and unified logging built in.

### For teams with dormant M cores
> Your i.MX8MN ships with a Cortex-M7 you are probably not using. With
> Pantavisor MCU it becomes a container -- loaded, monitored, updated, and
> rolled back as part of every revision. Add one line to your kas config.

### For teams with existing MCU+Linux products
> You already have an MCU talking to Linux over a custom serial protocol.
> Pantavisor MCU replaces that with a service mesh connection -- same UART,
> same firmware, but now with atomic OTA, bidirectional rollback, health
> monitoring, and unified logging. Stop reinventing the wheel.

### The service mesh pitch
> Once your MCU is a Pantavisor container, it joins the xconnect service
> mesh. It declares what Linux services it needs. It exposes its hardware
> to Linux containers. NetworkManager, BlueZ, cloud SDKs, AI inference --
> all reachable from firmware with one function call, none of it living in
> the firmware.

### The DBus pitch
> Pantavisor MCU is the most trivial way to interface with DBus backend
> services for MCUs that exists for RTOS firmware. No Unix sockets, no SASL,
> no connection management. Declare the service in run.json. Call the function.

### The logging pitch
> MCU logs in production usually go nowhere. Enable
> CONFIG_PANTAVISOR_LOG_BACKEND=y and every LOG_INF() in your Zephyr
> firmware flows into the Pantavisor log server alongside container logs --
> timestamped, tagged, forwarded to cloud. Production observability for MCU
> firmware from the first boot.

### MCU comfy mode
> Plug four RP2040 Picos into a Raspberry Pi. Each is an MCU container --
> focused firmware, health monitoring, atomic OTA, unified logging. Linux
> brokers every service connection. $20 of hardware. Full production revision
> model from day one.

---

## Roadmap

**Phase 1 -- Foundation**
PVCM protocol, Zephyr and FreeRTOS SDKs, pvcm-manager, shell demo on
i.MX8MN M7: `pv status`, `pv containers` over ttyRPMSG. RP2040 Pico via
USB as first external MCU target.

**Phase 2 -- Full OTA Coupling**
MCU firmware update, U-Boot integration, zero-config onboarding,
bidirectional rollback, meta-pantavisor Yocto integration.

**Phase 3 -- Service Mesh and DBus**
MCU services.json / run.json model, xconnect-graph integration,
Tier 1 DBus SDK, Tier 2 REST wrapper catalog, log backend,
LVGL display framework, multi-MCU demo, Pantavisor dashboard on M7.

---

*Pantavisor MCU -- Pantacor GmbH*
