# Pantavisor MCU -- Technical Plan

## Overview

Pantavisor MCU introduces the MCU as a fourth container type alongside LXC,
runc, and Wasm. The primary goal is to give teams that already have or are
building Linux+MCU products the same atomic revision model, health checking,
OTA safety, and service mesh that Pantavisor already provides for Linux
containers -- without reinventing any of it per project.

Three target scenarios drive the design:

**Dormant internal M core.** i.MX8MN, i.MX8MP, i.MX8QM and similar SoCs
ship with one or two Cortex-M cores that most teams never enable because
wiring up remoteproc, RPMsg, firmware loading, OTA coupling, and health
monitoring requires significant per-project engineering. Pantavisor MCU
makes the M core a container -- everything follows from that.

**Existing external MCU + Linux.** Many products already have a Cortex-M
connected to a Linux SoC via UART. These teams have custom protocols, no OTA
rollback safety, no service mesh, and no unified observability. Pantavisor
MCU gives the existing connection a standard transport, atomic revision
coupling, and service mesh membership.

**New product design.** Teams designing from scratch want a foundation that
covers both Linux and MCU from day one -- prototype with dev boards, ship
on production silicon, carry the same revision model throughout.

The secondary benefit -- once the MCU is in the revision and service mesh --
is that it can access the full Linux service ecosystem (DBus system services,
REST container APIs, log infrastructure) via simple function calls, without
any of that complexity living in the firmware.

---

## Core Concepts

### MCU as a Container

The MCU is modeled as a special container type in the Pantavisor revision.
Same policy model as Linux containers -- restart on crash, rollback on health
failure, OTA-coupled to the revision.

```
Pantavisor revision
├── container: app              (Linux, A53)
├── container: mqtt-bridge      (Linux, A53)
└── mcu: ui-frontend            (Zephyr, M7 or external MCU)
      firmware: bsp/m7_fw.elf
      transport: rpmsg | uart
      policy: { tryboot: rollback, operational: restart }
```

The MCU container participates in the same revision lifecycle as every other
container -- it is versioned, deployed, health-checked, and rolled back as
part of the revision, not separately.

### Single Source of Truth for Boot State

The MCU owns the revision boot state -- replacing uboot.txt / U-Boot env as
the authority for both Linux and MCU boot decisions. U-Boot and Pantavisor
both query the MCU at startup via the PVCM protocol. Falls back to the
existing uboot.txt / U-Boot env backend if no MCU is present. Existing
boards are completely unaffected.

The mapping to existing Pantavisor boot state semantics:

```
Current (uboot.txt + U-Boot env):   MCU flash equivalent:
uboot.txt: pv_rev                -> stable_rev + stable_slot
uboot.txt: pv_try                -> tryboot_rev + tryboot_slot + tryboot_pending
U-Boot env: pv_trying            -> tryboot_trying
```

`tryboot_trying` is the critical field. It is set atomically before jumping
to the tryboot partition, and cleared only on COMMIT. Any uncontrolled reset
(power loss, watchdog, kernel panic) leaves it set. Next boot: MCU reports
`tryboot_trying=1` to U-Boot, which rolls back. Identical behavior to the
current `pv_trying` mechanism.

### The Service Mesh -- MCU as a First-Class Peer

Once the MCU is a container, it joins the existing pv-xconnect service mesh.
The same `services.json` / `run.json` model Linux containers use works for
MCU containers too. pv-xconnect reads the xconnect-graph and pvcm-manager
sets up the corresponding RPMsg or UART bridge routes for MCU consumers and
providers.

The MCU can consume Linux services (NetworkManager, BlueZ, cloud SDKs,
custom containers) and export its own services (sensors, display control,
motor setpoint) back to Linux containers. All connections are visible in
`/xconnect-graph` alongside every Linux container connection.

### Zero-Config Onboarding

First boot works with no MCU. When an MCU container is added to any
revision, pvcm-manager detects the virgin MCU, installs firmware, and
migrates boot state automatically. No factory re-flash ever needed.

---

## Repository Layout

All code in the **pantavisor main git repo**. Meta-pantavisor handles
Yocto build integration via kas snippets and Zephyr multiconfig.

```
pantavisor/
├── src/
│   ├── bootstate.c/h                <- bootstate abstraction (refactored)
│   ├── bootstate_uboot.c            <- existing uboot.txt/env backend
│   └── bootstate_mcu.c              <- new MCU backend
├── pvcm-manager/                    <- Linux-side daemon
│   ├── main.c
│   ├── pvcm_transport_uart.c        <- UART transport (external MCU)
│   ├── pvcm_transport_rpmsg.c       <- RPMsg transport (internal M core)
│   ├── pvcm_health.c                <- health monitoring, phase management
│   ├── pvcm_firmware.c              <- MCU firmware install/update
│   ├── pvcm_bridge.c                <- xconnect REST + DBus gateway
│   └── pvcm_log.c                   <- log stream forwarding to PV log server
├── sdk/zephyr/                      <- Pantavisor Zephyr SDK (west module)
│   ├── zephyr/module.yml
│   ├── CMakeLists.txt
│   ├── Kconfig
│   ├── include/pantavisor/
│   │   ├── pvcm.h                   <- public API
│   │   ├── pvcm_protocol.h          <- wire format (shared with Linux/U-Boot)
│   │   └── pvcm_state.h
│   └── src/
│       ├── pvcm_server.c            <- mandatory: revision state server
│       ├── pvcm_state.c             <- flash state r/w
│       ├── pvcm_transport_uart.c
│       ├── pvcm_transport_rpmsg.c
│       ├── pvcm_heartbeat.c         <- mandatory: heartbeat + crash counter
│       ├── pvcm_log_backend.c       <- mandatory: Zephyr log -> PV log server
│       ├── pvcm_client.c            <- optional: REST API client
│       ├── pvcm_dbus.c              <- optional: DBus call/subscribe/expose
│       ├── pvcm_events.c            <- optional: lifecycle callbacks
│       └── pvcm_shell.c             <- optional: 'pv' shell commands
├── sdk/freertos/                    <- Pantavisor FreeRTOS SDK
│   └── ...                          <- same structure, FreeRTOS primitives
└── protocol/
    └── pvcm_protocol.h              <- canonical wire format, shared by all

meta-pantavisor/
├── kas/snippets/
│   └── pvcm-mcu.yml                 <- kas snippet: enables MCU multiconfig
├── conf/multiconfig/
│   └── mcu.conf                     <- Zephyr multiconfig
├── recipes-pantavisor/
│   ├── pvcm-manager/
│   │   └── pvcm-manager_%.bb
│   └── pantavisor-zephyr-sdk/
│       └── pantavisor-zephyr-sdk.bb
└── recipes-bsp/
    └── pantavisor-bsp/
        └── pantavisor-bsp.bbappend  <- adds MCU ELF to BSP container
```

---

## PVCM Protocol

Shared header `protocol/pvcm_protocol.h`. Binary framed protocol over UART
or RPMsg. Same wire format regardless of physical transport.

### Framing

```
[ 0xAA | 0x55 | len 2B | payload | crc32 4B ]
```

UART framing uses sync bytes + length for stream reassembly. RPMsg uses the
same framing for consistency but the kernel handles message boundaries.

### Transport Abstraction

Both transports implement the same interface:

```c
typedef struct pvcm_transport {
    const char *name;
    int  (*init)(struct pvcm_transport *t, const char *device);
    int  (*send)(struct pvcm_transport *t, const void *buf, size_t len);
    void (*set_recv_cb)(struct pvcm_transport *t,
                        pvcm_recv_cb_t cb, void *ctx);
    void (*close)(struct pvcm_transport *t);
} pvcm_transport_t;

extern pvcm_transport_t pvcm_transport_rpmsg;   /* /dev/rpmsg0 */
extern pvcm_transport_t pvcm_transport_uart;    /* /dev/ttyS1 or ttyACM0 */
```

pvcm-manager probes RPMsg first (internal M core), then UART (external MCU).
Everything above the transport layer is identical.

### Message Set

```c
typedef enum {
    /* handshake */
    PVCM_OP_HELLO               = 0x01,
    PVCM_OP_HELLO_RESP          = 0x02,

    /* boot state -- queried by U-Boot and Pantavisor at startup */
    PVCM_OP_QUERY_STATE         = 0x03,
    PVCM_OP_STATE_RESP          = 0x04,

    /* Pantavisor write path -- mirrors pv_try/pv_trying/pv_rev semantics */
    PVCM_OP_SET_TRYBOOT         = 0x05,   /* equiv: write pv_try to uboot.txt */
    PVCM_OP_COMMIT              = 0x06,   /* equiv: update pv_rev, clear pv_trying */
    PVCM_OP_ROLLBACK            = 0x07,   /* explicit rollback request */
    PVCM_OP_ACK                 = 0x08,
    PVCM_OP_NACK                = 0x09,

    /* health -- MCU pushes unsolicited every 5s */
    PVCM_EVT_HEARTBEAT          = 0x10,
    PVCM_EVT_BRIDGE_READY       = 0x11,
    PVCM_EVT_BRIDGE_LOST        = 0x12,
    PVCM_EVT_SERVICE_LIST       = 0x13,
    PVCM_EVT_REVISION_CHANGE    = 0x14,
    PVCM_OP_REQUEST_ROLLBACK    = 0x15,   /* MCU requests Linux rollback */

    /* firmware update -- multiplexed, no special mode required */
    PVCM_OP_FW_UPDATE_START     = 0x20,   /* Linux -> MCU: begin upload to inactive slot */
    PVCM_OP_FW_UPDATE_DATA      = 0x21,   /* Linux -> MCU: chunk of firmware data */
    PVCM_OP_FW_UPDATE_END       = 0x22,   /* Linux -> MCU: upload complete, verify */
    PVCM_EVT_FW_PROGRESS        = 0x23,   /* MCU -> Linux: progress report per chunk */

    /* MCU detection -- used by pvcm-manager to distinguish PVCM vs MCUboot */
    PVCM_OP_SMP_REJECT          = 0x29,   /* MCU -> Linux: SMP probe rejected, speak PVCM */

    /* log stream -- MCU -> Linux -> PV log server */
    PVCM_OP_LOG                 = 0x28,

    /* gateway -- REST: MCU as client */
    PVCM_OP_REST_REQ            = 0x30,   /* MCU -> Linux: outbound REST request */
    PVCM_OP_REST_RESP           = 0x31,   /* Linux -> MCU: outbound REST response */
    /* gateway -- REST: MCU as server */
    PVCM_OP_REST_INVOKE         = 0x32,   /* Linux -> MCU: inbound REST request */
    PVCM_OP_REST_INVOKE_RESP    = 0x33,   /* MCU -> Linux: inbound REST response */

    /* gateway -- DBus */
    PVCM_OP_DBUS_CALL           = 0x40,
    PVCM_OP_DBUS_CALL_RESP      = 0x41,
    PVCM_OP_DBUS_SUBSCRIBE      = 0x42,
    PVCM_OP_DBUS_UNSUBSCRIBE    = 0x43,
    PVCM_OP_DBUS_SIGNAL         = 0x44,   /* Linux -> MCU: signal fired */
    PVCM_OP_DBUS_EXPOSE         = 0x45,   /* MCU registers a DBus endpoint */
    PVCM_OP_DBUS_INVOKE         = 0x46,   /* Linux calls into MCU endpoint */
    PVCM_OP_DBUS_INVOKE_RESP    = 0x47,
} pvcm_op_t;
```

### Key Structs

```c
/* STATE_RESP -- answers all U-Boot and Pantavisor boot questions */
typedef struct {
    uint8_t  op;
    uint8_t  status;
    uint8_t  stable_slot;       /* 0=A 1=B */
    uint8_t  tryboot_slot;
    uint8_t  tryboot_pending;   /* equiv: pv_try is set in uboot.txt */
    uint8_t  tryboot_trying;    /* equiv: pv_trying env -- set BEFORE jump */
    uint32_t stable_rev;
    uint32_t tryboot_rev;
    uint8_t  mcu_fw_version;
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_state_resp_t;

/* HEARTBEAT -- pushed every 5s, zero app code required */
typedef struct {
    uint8_t  op;
    uint8_t  status;            /* PVCM_HEALTH_OK / DEGRADED */
    uint16_t uptime_s;
    uint8_t  crash_count;       /* since last revision change */
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_heartbeat_t;

/* LOG -- MCU log line forwarded to Pantavisor log server */
typedef struct {
    uint8_t  op;
    uint8_t  level;             /* 0=ERR 1=WRN 2=INF 3=DBG */
    uint16_t msg_len;
    char     module[16];        /* source module name */
    char     msg[224];          /* log message, null terminated */
    uint32_t crc32;
} __packed pvcm_log_t;

/* REST_REQ -- generic REST call, fits one RPMsg buffer */
typedef struct {
    uint8_t  op;
    uint8_t  req_id;
    uint8_t  method;            /* 0=GET 1=POST 2=PUT 3=DELETE */
    uint8_t  reserved;
    char     path[60];
    char     body[192];
    uint32_t crc32;
} __packed pvcm_rest_req_t;

/* DBUS_CALL -- MCU calls a DBus method */
typedef struct {
    uint8_t  op;
    uint8_t  req_id;
    char     path[60];
    char     args[188];         /* JSON args */
    uint32_t crc32;
} __packed pvcm_dbus_call_t;

/* DBUS_SUBSCRIBE -- MCU subscribes to a DBus signal */
typedef struct {
    uint8_t  op;
    uint8_t  sub_id;
    char     path[60];
    uint32_t crc32;
} __packed pvcm_dbus_sub_t;

/* DBUS_SIGNAL -- Linux pushes signal to MCU */
typedef struct {
    uint8_t  op;
    uint8_t  sub_id;
    uint16_t payload_len;
    char     payload[248];      /* JSON signal data */
    uint32_t crc32;
} __packed pvcm_dbus_signal_t;

/* DBUS_EXPOSE -- MCU registers a DBus service endpoint */
typedef struct {
    uint8_t  op;
    uint8_t  endpoint_id;
    char     path[60];
    uint32_t crc32;
} __packed pvcm_dbus_expose_t;

/* DBUS_INVOKE -- Linux calls into an MCU-exposed endpoint */
typedef struct {
    uint8_t  op;
    uint8_t  invoke_id;
    uint8_t  endpoint_id;
    uint8_t  reserved;
    char     args[248];
    uint32_t crc32;
} __packed pvcm_dbus_invoke_t;

/* FW_UPDATE_START -- begin firmware upload to inactive MCUboot slot */
typedef struct {
    uint8_t  op;
    uint8_t  slot;              /* 1 = secondary slot (inactive) */
    uint32_t total_size;        /* total firmware size in bytes */
    uint32_t chunk_size;        /* agreed chunk size for DATA frames */
    uint8_t  sha256[32];        /* expected SHA256 of complete image */
    uint32_t crc32;
} __packed pvcm_fw_start_t;

/* FW_UPDATE_DATA -- one chunk of firmware data */
typedef struct {
    uint8_t  op;
    uint8_t  reserved;
    uint16_t seq;               /* sequence number, wraps at 65535 */
    uint32_t offset;            /* byte offset in firmware image */
    uint16_t len;               /* bytes in this chunk, <= chunk_size */
    uint8_t  data[512];         /* firmware bytes */
    uint32_t crc32;
} __packed pvcm_fw_data_t;

/* FW_UPDATE_END -- upload complete, MCU verifies SHA256 */
typedef struct {
    uint8_t  op;
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_fw_end_t;

/* EVT_FW_PROGRESS -- MCU pushes after each chunk, interleaved with other traffic */
typedef struct {
    uint8_t  op;
    uint8_t  percent;           /* 0-100 */
    uint32_t bytes_written;
    uint32_t total_bytes;
    uint32_t crc32;
} __packed pvcm_fw_progress_t;
```

---

## MCU Flash State

Persistent state in MCU internal flash (or dedicated SPI NOR). Maps
directly to what Pantavisor currently stores in uboot.txt + U-Boot env,
plus health tracking fields.

```c
typedef struct {
    uint32_t magic;             /* 0x5056434D "PVCM" */
    uint32_t version;

    /* boot state -- mirrors uboot.txt pv_rev/pv_try + pv_trying env */
    uint32_t stable_rev;
    uint8_t  stable_slot;       /* 0=A 1=B */
    uint32_t tryboot_rev;
    uint8_t  tryboot_slot;
    uint8_t  tryboot_pending;   /* pv_try is set, tryboot not yet attempted */
    uint8_t  tryboot_trying;    /* set BEFORE jump, cleared only on COMMIT */
                                /* if set on boot -> last tryboot failed */

    /* health tracking */
    uint8_t  crash_count;       /* reset on COMMIT, incremented in Reset_Handler */
    uint8_t  crash_threshold;   /* auto-rollback if exceeded during tryboot */

    uint32_t crc32;
} pvcm_flash_state_t;
```

### tryboot_trying -- The Critical Field

This field is the MCU equivalent of `pv_trying` in U-Boot env. The sequence:

```
SET_TRYBOOT received from Pantavisor:
  tryboot_pending=1, tryboot_trying=0, writes flash

QUERY_STATE called by U-Boot at next boot:
  MCU atomically: trying=1, pending=0, writes flash
  THEN responds with tryboot info
  --> flash committed BEFORE U-Boot boots kernel
  --> any subsequent reset leaves trying=1 --> rollback

COMMIT received from Pantavisor after healthy boot:
  stable_rev/slot updated
  tryboot_trying=0, tryboot_pending=0, crash_count=0
```

### Reset_Handler -- Boot Safety

The MCU increments crash_count and checks tryboot_threshold as the very
first action in Reset_Handler, before any peripheral initialization:

```c
void Reset_Handler(void) {
    /* read and immediately clear TRYBOOT_GPIO if used */
    bool gpio_tryboot = gpio_read_and_clear(TRYBOOT_PIN);

    /* read flash state -- must work before SystemInit() */
    pvcm_flash_state_t *s = pvcm_state_get_raw();

    if (s->magic == PVCM_MAGIC) {
        s->crash_count++;
        pvcm_state_write_raw(s);

        /* if in tryboot and crashing repeatedly: self-rollback */
        if (s->tryboot_trying
            && s->crash_count >= s->crash_threshold) {
            s->tryboot_trying  = 0;
            s->tryboot_pending = 0;
            pvcm_state_write_raw(s);
            /* boot stable slot directly, never reaches SystemInit */
            load_firmware_slot(s->stable_slot);
        }
    }

    SystemInit();
    /* normal boot continues */
}
```

### tryboot_trying and Reset Types

A concern with GPIO-only approaches is that warm resets (watchdog, kernel
panic) may preserve GPIO state. The tryboot_trying field in persistent flash
resolves this: it is already written before jumping to tryboot firmware, so
any reset type -- cold boot, warm reset, watchdog, power loss -- leaves the
correct state in flash. The TRYBOOT_GPIO is an optional additional signal
for the warm-reboot case but the flash state is the authoritative record.

---

## Zephyr SDK

### Mandatory Modules (zero app code)

**pvcm_server task**
Binary protocol server on dedicated UART or RPMsg endpoint. Handles all
PVCM messages. Runs automatically from first boot. Customer never calls it.

**pvcm_heartbeat task**
Sends `PVCM_EVT_HEARTBEAT` every 5 seconds including uptime, crash_count,
and optional app health status. Starts automatically.

**pvcm_log_backend**
Zephyr log backend that routes all `LOG_INF()`, `LOG_WRN()`, `LOG_ERR()`
output to pvcm-manager via `PVCM_OP_LOG` frames. pvcm-manager forwards to
the Pantavisor log server alongside container logs. Enable with:

```kconfig
CONFIG_PANTAVISOR_LOG_BACKEND=y
CONFIG_LOG_DEFAULT_LEVEL=3
```

No code changes to existing firmware. All existing log calls output
automatically to the Pantavisor log server from first boot.

### Optional Modules

```
pvcm_client.c      REST API client -- pvcm_get(), pvcm_post()
pvcm_dbus.c        DBus call/subscribe/expose (see pvcm-dbus.md)
pvcm_events.c      lifecycle callbacks -- bridge up/down, revision change
pvcm_shell.c       'pv' shell commands over ttyRPMSG for debug
```

### Kconfig

```kconfig
config PANTAVISOR
    bool "Pantavisor RTOS SDK"

config PANTAVISOR_TRANSPORT_UART
    bool "UART transport"
    depends on PANTAVISOR
    help
      For external MCUs connected via UART. Supports hardware UARTs and
      PIO-based software UARTs (RP2040). Device configured via
      CONFIG_PANTAVISOR_UART_DEVICE.

config PANTAVISOR_TRANSPORT_RPMSG
    bool "RPMsg transport"
    depends on PANTAVISOR && OPENAMP
    help
      For internal M cores (i.MX8MN M7, i.MX8QM M4 etc).

config PANTAVISOR_LOG_BACKEND
    bool "Log backend -- forward to Pantavisor log server"
    default y
    depends on PANTAVISOR && LOG

config PANTAVISOR_BRIDGE
    bool "REST API client"
    depends on PANTAVISOR

config PANTAVISOR_DBUS
    bool "DBus gateway client"
    depends on PANTAVISOR

config PANTAVISOR_DISPLAY
    bool "Display frontend support"
    depends on PANTAVISOR && LVGL

config PANTAVISOR_SHELL
    bool "Shell commands"
    depends on PANTAVISOR && SHELL
```

### Customer App -- Minimal

```c
#include <pantavisor/pvcm.h>

void main(void) {
    /* pvcm_server, pvcm_heartbeat, pvcm_log_backend running automatically */

    /* optional: register app health callback */
    pvcm_register_health_cb(my_health_check);

    /* application code */
    my_application_start();
}
```

### Firmware Update Handler (Zephyr SDK)

The PVCM SDK handles all firmware update opcodes automatically. The
application never needs to implement flash write logic. MCUboot's flash
map API is used to write to slot 1 safely while slot 0 runs:

```c
/* pvcm_firmware.c -- runs in pvcm_server task context */

static const struct flash_area *fw_slot;
static uint32_t fw_expected_size;
static uint8_t  fw_expected_sha256[32];
static struct sha256_ctx fw_sha;
static uint32_t fw_bytes_written;

void pvcm_on_fw_update_start(pvcm_fw_start_t *msg) {
    size_t slot_size;

    if (flash_area_open(FLASH_AREA_ID(image_1), &fw_slot) != 0) {
        pvcm_nack(PVCM_ERR_NO_SLOT);
        return;
    }
    flash_area_get_size(fw_slot, &slot_size);

    if (msg->total_size > slot_size) {
        flash_area_close(fw_slot);
        pvcm_nack(PVCM_ERR_TOO_LARGE);
        return;
    }

    /* erase slot 1 -- progressive erase per chunk is also supported */
    flash_area_erase(fw_slot, 0, slot_size);

    fw_expected_size = msg->total_size;
    memcpy(fw_expected_sha256, msg->sha256, 32);
    sha256_init(&fw_sha);
    fw_bytes_written = 0;

    pvcm_ack();
}

void pvcm_on_fw_update_data(pvcm_fw_data_t *msg) {
    flash_area_write(fw_slot, msg->offset, msg->data, msg->len);
    sha256_update(&fw_sha, msg->data, msg->len);
    fw_bytes_written += msg->len;

    /* ACK first so manager can send next chunk immediately */
    pvcm_ack();

    /* then push progress -- interleaved naturally with next chunk */
    pvcm_fw_progress_t prog = {
        .op            = PVCM_EVT_FW_PROGRESS,
        .percent       = (fw_bytes_written * 100) / fw_expected_size,
        .bytes_written = fw_bytes_written,
        .total_bytes   = fw_expected_size,
    };
    pvcm_send(&prog, sizeof(prog));
}

void pvcm_on_fw_update_end(pvcm_fw_end_t *msg) {
    uint8_t digest[32];
    sha256_final(&fw_sha, digest);
    flash_area_close(fw_slot);

    if (memcmp(digest, fw_expected_sha256, 32) != 0) {
        pvcm_nack(PVCM_ERR_CHECKSUM);
        return;
    }
    /* slot 1 written and verified -- awaiting SET_TRYBOOT */
    pvcm_ack();
}

void pvcm_on_set_tryboot(void) {
    /* MCUboot handles the swap on next reboot */
    boot_request_upgrade(BOOT_UPGRADE_TEST);
    pvcm_ack();
    sys_reboot(SYS_REBOOT_COLD);
}

void pvcm_on_commit(void) {
    /* confirm running image -- MCUboot will not revert */
    boot_write_img_confirmed();
    pvcm_ack();
}
```

### FreeRTOS SDK

Same structure, same Kconfig options, FreeRTOS task primitives instead of
Zephyr k_thread. Log API:

```c
pvcm_log_info("motor", "speed=%d torque=%d", speed, torque);
pvcm_log_warn("sensor", "spike detected: %d mA", current);
pvcm_log_error("sensor", "timeout after %d ms", elapsed);
```

---

## Linux Side: pvcm-manager

### Startup Sequence

```c
void pvcm_manager_init(void) {
    pvcm_transport_t *transport = NULL;

    /* 1. probe RPMsg (internal M core) */
    if (access("/dev/rpmsg0", F_OK) == 0) {
        pvcm_transport_rpmsg.init(&pvcm_transport_rpmsg, "/dev/rpmsg0");
        if (pvcm_probe(&pvcm_transport_rpmsg) == 0) {
            transport = &pvcm_transport_rpmsg;
            LOG_INF("PVCM: RPMsg transport");
        }
    }

    /* 2. fall back to UART (external MCU) */
    if (!transport) {
        const char *dev = pvcm_config_uart_device();
        pvcm_transport_uart.init(&pvcm_transport_uart, dev);
        if (pvcm_probe(&pvcm_transport_uart) == 0) {
            transport = &pvcm_transport_uart;
            LOG_INF("PVCM: UART transport on %s", dev);
        }
    }

    /* 3. no MCU -- use default backend, no behavior change */
    if (!transport) {
        LOG_INF("PVCM: no MCU, using default bootstate backend");
        bootstate_use_default();
        return;
    }

    /* 4. MCU present -- check if virgin */
    pvcm_state_resp_t state;
    bool virgin = (pvcm_query_state(transport, &state) != 0
                   || state.magic != PVCM_MAGIC
                   || state.stable_rev == 0);

    if (virgin) {
        /* install firmware if present in BSP container */
        const char *fw = pvcm_config_firmware_path();
        if (fw) {
            pvcm_firmware_install(transport, fw);
            pvcm_migrate_bootstate(transport);
        } else {
            /* MCU present but no firmware in this revision */
            bootstate_use_default();
            return;
        }
    }

    /* 5. MCU is authority */
    bootstate_use_mcu(transport);
    pvcm_dispatch_init(transport);
    pvcm_bridge_init(transport);     /* REST + DBus gateway */
    pvcm_health_init(transport);     /* heartbeat monitor */
    pvcm_log_init(transport);        /* log stream forwarder */
}
```

### Responsibilities

```
Boot time:
  probe MCU (UART or RPMsg)
  if virgin MCU: install firmware + migrate boot state
  switch bootstate backend to MCU
  start health monitoring
  start log stream forwarding
  start xconnect gateway

Tryboot flow:
  stream new MCU firmware to inactive slot (slot 1) via PVCM_FW_UPDATE_*
  upload is fully multiplexed -- heartbeat, gateway traffic continue during upload
  EVT_FW_PROGRESS events forwarded to xconnect for UI progress reporting
  on FW_UPDATE_END: MCU verifies SHA256, ACKs or NACKs
  send PVCM_OP_SET_TRYBOOT -> MCU calls boot_request_upgrade(BOOT_UPGRADE_TEST)
  MCU reboots -> MCUboot swaps slot 0 <-> slot 1
  wait for PVCM HELLO + HEARTBEAT from new firmware
  verify MCU revision matches expected

Commit (called by Pantavisor after health checks pass):
  verify MCU: heartbeat present + crash_count < threshold + status OK
  send PVCM_OP_COMMIT to MCU
  MCU writes new stable state to flash

Log forwarding:
  receive PVCM_OP_LOG frames from MCU
  forward to Pantavisor log server with container name tag "mcu-<name>"
  timestamps correlated with Linux container logs

Health monitoring -- two phases:
  TRYBOOT:     any failure -> immediate rollback
               heartbeat missing, crash_count > 0, status DEGRADED
               MCU revision mismatch after reset

  COMMITTED:   resilient, like container restart policy
               heartbeat missing -> restart MCU via GPIO reset
               crash_count high -> restart MCU
               max restarts exceeded -> alert, stay running
               MCU requests rollback -> trigger Linux rollback
```

### Health Policy

```c
/* tryboot phase -- zero tolerance */
if (phase == TRYBOOT) {
    if (heartbeat_missing || crash_count > 0 || status == DEGRADED)
        pantavisor_trigger_rollback("mcu_health_failure");
}

/* operational phase -- resilient, like container restart policy */
if (phase == COMMITTED) {
    if (heartbeat_missing && restart_count < max_restarts)
        pvcm_restart_mcu();   /* assert reset GPIO */
    if (restart_count >= max_restarts)
        pantavisor_send_alert("mcu_max_restarts");
}
```

### Firmware Update -- Multiplexed, Native PVCM

Firmware upload uses the PVCM_FW_UPDATE_* opcodes over the same transport
as all other traffic. There is no special upload mode, no channel suspension,
no protocol break. The MCU dispatch loop treats firmware chunks as just
another opcode alongside heartbeats, REST responses, and DBus signals.

**Why this works on UART:** each PVCM_FW_UPDATE_DATA frame gets an explicit
ACK before the next chunk is sent. pvcm-manager waits for ACK between chunks,
giving the MCU a natural window to push any pending outbound frames
(EVT_HEARTBEAT, EVT_FW_PROGRESS, REST_RESP etc.) before the next chunk
arrives. The half-duplex nature of UART is handled by the request/response
discipline already built into the protocol.

**Why this works on RPMsg:** RPMsg has independent named endpoints -- firmware
data flows on one endpoint, control and gateway traffic on another. True
concurrent multiplexing with no coordination needed.

**MCUboot integration:** the MCU writes each chunk directly to MCUboot slot 1
via the Zephyr flash map API. MCUboot's slot 1 partition is the inactive slot
-- the running firmware in slot 0 is never touched. On `PVCM_OP_SET_TRYBOOT`
the MCU calls `boot_request_upgrade(BOOT_UPGRADE_TEST)` and reboots. MCUboot
validates the image in slot 1, swaps, and boots the new firmware. If the new
firmware does not call `boot_write_img_confirmed()` (via `PVCM_OP_COMMIT`),
MCUboot reverts to slot 0 on the next reset.

**Emergency interruption:** even during upload, the MCU can push
`PVCM_OP_REQUEST_ROLLBACK` at any time. pvcm-manager watches all incoming
frames between chunk sends. If a rollback request arrives, the upload is
aborted and the emergency is handled immediately. The incomplete slot 1 write
is harmless -- MCUboot will not boot an image that fails SHA256 verification.

```
pvcm-manager                    MCU (running slot 0)
────────────                    ────────────────────
FW_UPDATE_START { size, sha256 }
                         →      erase slot 1
                         ←      ACK

FW_UPDATE_DATA { offset:0 }
                         →      flash_area_write(slot1, 0, data)
                         ←      ACK
                         ←      EVT_FW_PROGRESS { percent: 1 }

[Linux container asks for sensor reading]
REST_REQ { GET /sensor/temp }
                         →      read sensor
                         ←      REST_RESP { 23.4 }

FW_UPDATE_DATA { offset:512 }
                         →      flash_area_write(slot1, 512, data)
                         ←      ACK
                         ←      EVT_FW_PROGRESS { percent: 2 }

                         ←      EVT_HEARTBEAT   (still ticking)

... (N chunks later) ...

FW_UPDATE_END
                         →      sha256_verify(slot1)
                         ←      ACK  (or NACK if checksum fails)

SET_TRYBOOT
                         →      boot_request_upgrade(BOOT_UPGRADE_TEST)
                                sys_reboot()
```

**Progress reporting to UI:** `EVT_FW_PROGRESS` frames are forwarded by
pvcm-manager to any xconnect consumer that declared interest -- typically a
UI container. The UI receives a push event per chunk and updates its progress
bar. At 921600 baud with 512-byte chunks a 256KB firmware produces ~512
progress events over ~3 seconds. Smooth enough for any progress indicator.

**MCU detection and install state:** pvcm-manager uses the following probe
sequence to determine what state the MCU is in:

```
1. Send PVCM HELLO
   PVCM response              -> normal operation, speak PVCM only

2. Send SMP echo (mcumgr framing)
   SMP response               -> MCUboot serial recovery running
                                 image list to check slot state:
                                 hash: Unavailable -> virgin, needs install
                                 valid hash        -> PVCM crashed, SMP reset

3. No response to either
   -> MCU absent or powered off
```

Once PVCM firmware is installed and running, the MCU rejects any SMP probe
with `PVCM_OP_SMP_REJECT` -- a standard PVCM frame telling pvcm-manager
"I speak PVCM, not SMP". All subsequent firmware updates go through
PVCM_FW_UPDATE_* regardless of whether the MCU has MCUboot underneath.
SMP is only ever used as a detection probe and for the one-time initial
install from a virgin MCUboot state.

### xconnect Gateway Integration

pvcm-manager reads the xconnect-graph and sets up bridge routes for every
link where the MCU container is consumer or provider:

```c
void pvcm_bridge_init(pvcm_transport_t *t) {
    xconnect_graph_t *graph = pvcm_fetch_xconnect_graph();

    for each link in graph where consumer == MCU_CONTAINER_NAME:
        if link.type == "dbus":
            /* connect to injected DBus socket, register route */
            pvcm_dbus_route_add(link.name, link.interface,
                                link.target, link.role);
        if link.type == "rest":
            pvcm_rest_route_add(link.name, link.socket);

    for each link in graph where provider == MCU_CONTAINER_NAME:
        /* register MCU service on Linux system bus */
        pvcm_dbus_register_service(link.name, link.interface);

    /* re-run when xconnect-graph changes */
    pvcm_watch_xconnect_graph(pvcm_bridge_reconcile);
}
```

See `pvcm-dbus.md` for the full DBus bridge implementation.

---

## Bootstate Abstraction

Small refactor to existing Pantavisor bootstate code. Pluggable backend
selected at runtime based on MCU availability:

```c
typedef struct pv_bootstate_backend {
    const char *name;
    int (*get_state)(struct pv_bootstate *state);
    int (*set_tryboot)(uint32_t rev, uint8_t slot);
    int (*commit)(uint32_t rev, uint8_t slot);
    int (*rollback)(void);
} pv_bootstate_backend_t;

/* three backends */
extern pv_bootstate_backend_t backend_mcu;        /* new */
extern pv_bootstate_backend_t backend_uboot_env;  /* existing */
extern pv_bootstate_backend_t backend_uboot_txt;  /* existing RPi-style */

void pv_bootstate_init(void) {
    if (pvcm_probe() == 0 && pvcm_state_valid()) {
        active_backend = &backend_mcu;
        return;
    }
    active_backend = platform_default_backend(); /* unchanged */
}
```

Existing uboot.txt and U-Boot env backends remain as fallbacks. No behavior
change for boards without MCU.

---

## U-Boot Integration

U-Boot queries MCU over UART before selecting which partition to boot.
Falls back to existing uboot.txt / env if no MCU responds.

```c
int board_late_init(void) {
    pvcm_state_resp_t state;

    if (pvcm_probe() == 0
        && pvcm_query_state(&state) == 0
        && state.magic == PVCM_MAGIC
        && state.stable_rev != 0) {

        /* MCU is authority */
        if (state.tryboot_trying) {
            /* uncommitted tryboot -> rollback to stable */
            printf("PVCM: tryboot not committed -> rollback\n");
            boot_stable(&state);
            pvcm_rollback();    /* inform MCU */

        } else if (state.tryboot_pending) {
            /* fresh tryboot -- MCU atomically sets trying=1 during query */
            printf("PVCM: tryboot rev %d slot %c\n",
                   state.tryboot_rev,
                   state.tryboot_slot ? 'B' : 'A');
            boot_tryboot(&state);

        } else {
            /* normal stable boot */
            boot_stable(&state);
        }

    } else {
        /* no MCU -- existing behavior unchanged */
        pv_bootstate_read_default();
    }
}
```

Note: during `QUERY_STATE` the MCU atomically transitions
`tryboot_pending=1` to `tryboot_trying=1` and writes flash before
responding. This ensures the flash state is committed before U-Boot boots
the kernel, matching the existing `pv_trying` semantics exactly.

---

## Zero-Config Onboarding

```
Revision 0 (no MCU container):
  U-Boot: no MCU -> uboot.txt fallback -> boots rev 0
  Pantavisor: no MCU probe -> default backend
  works exactly as today

Revision 1 (MCU container added):
  pvcm-manager probes MCU -> present but virgin (no valid flash state)
  installs firmware via PVCM_FW_UPDATE_* sequence
  migrates current boot state: stable_rev=1, slot=current -> MCU flash
  health checks pass (heartbeat arrives, crash_count=0)
  Pantavisor commits rev 1 -> sends PVCM_COMMIT to MCU
  MCU writes stable_rev=1 to flash
  MCU is now authority for all future revisions

Next cold boot:
  U-Boot probes MCU -> valid state, magic OK, stable_rev=1 -> uses it
  fully coupled, no manual steps ever needed

Removing MCU container (revision N):
  pvcm-manager reads current state from MCU
  writes stable_rev and slot back to uboot.txt / U-Boot env
  future boots: no MCU probe -> file backend correctly reflects state
```

---

## BSP Container Layout

```
bsp/
├── kernel.itb
├── imx8mn.dtb
├── mcu/                         <- optional, present only if MCU container
│   ├── firmware.elf             <- Zephyr or FreeRTOS ELF
│   ├── firmware.ver             <- revision number string
│   ├── firmware.sha256          <- integrity check
│   └── gateway.yaml             <- xconnect service declarations
└── pvcm-manager.conf            <- transport, policy, uart device config
```

U-Boot loads `mcu/firmware.elf` before the Linux kernel if present:

```bash
# U-Boot bootscript
if test -e mmc 0:${bsp_part} mcu/firmware.elf; then
    load mmc 0:${bsp_part} 0x80000000 mcu/firmware.elf
    bootaux 0x80000000
    # MCU running before Linux starts
fi
load mmc 0:${bsp_part} ${kernel_addr_r} kernel.itb
bootm ${kernel_addr_r}
```

For external MCUs connected via UART, U-Boot does not load firmware -- the
external MCU boots independently from its own flash, reading the PVCM flash
state to determine which firmware slot to run.

---

## Hardware Support

### Internal M Core (RPMsg)

```
i.MX8MN / i.MX8MP:  1x Cortex-M7, RPMsg over shared DDR
i.MX8QM:            2x Cortex-M4, two independent RPMsg channels
                    dual MCU containers in same revision possible
```

Multiple RPMsg channels for i.MX8QM:

```
/dev/rpmsg0  <->  M4 core 0  (e.g. display frontend)
/dev/rpmsg1  <->  M4 core 1  (e.g. motor controller)
```

Each has independent gateway config, independent health monitoring,
independent firmware artifact in BSP container.

### External MCU (UART)

Any UART-capable MCU. UART selection on common dev boards:

```
RP2040 Pico:    hardware UART0/1 + up to 4 PIO software UARTs
                PIO UARTs use any GPIO pin, zero CPU overhead
                recommended for prototyping: plug in via USB -> /dev/ttyACM0

STM32 Nucleo:   USART2 -> ST-Link VCP (debug/printf)
                USART1, USART3 free on Arduino headers
                configure in STM32CubeIDE, no software UART needed

nRF52 DK:       1 hardware UART (may be used by BLE debug)
                software UART via GPIO bit-bang if needed

ESP32 DevKit:   3 hardware UARTs, 1 used for programming, 2 free
```

For products designed from scratch: reserve one UART between SoC and MCU
at board design time. Two PCB traces. One Kconfig line. The PVCM UART is
a dedicated internal bus that does not compete with application UARTs.

### Multiple MCU Containers -- Comfy Mode

Nothing limits the number of MCU containers in a revision. For prototyping,
multiple RP2040 Picos on USB provide multiple independent MCU containers:

```
Linux SBC
  |-- /dev/ttyACM0  ->  MCU container 0: display
  |-- /dev/ttyACM1  ->  MCU container 1: motor
  |-- /dev/ttyACM2  ->  MCU container 2: sensors
  +-- /dev/ttyACM3  ->  MCU container 3: IO expander
```

All four revision-coupled, health-monitored, and OTA-updated atomically.
All four log output in the Pantavisor log server. Linux brokers all service
connections. No direct MCU-to-MCU protocol needed. This maps directly to
production architectures -- safety controller, motion controller, sensor
array, operator panel -- before any custom PCB is designed.

---

## Yocto / meta-pantavisor Integration

### kas snippet

```yaml
# meta-pantavisor/kas/snippets/pvcm-mcu.yml
header:
  version: 11

repos:
  meta-zephyr:
    url: https://github.com/zephyrproject-rtos/meta-zephyr
    branch: main

local_conf_fragment: |
  BBMULTICONFIG += "mcu"
  do_image_bsp[mcdepends] += \
    "mc::mcu:pantavisor-zephyr-app:do_deploy"
```

### Zephyr multiconfig

```bash
# meta-pantavisor/conf/multiconfig/mcu.conf
MACHINE           = "${MCU_MACHINE}"
DISTRO            = "zephyr"
ZEPHYR_BOARD      = "${MCU_ZEPHYR_BOARD}"
ZEPHYR_APP        = "${MCU_ZEPHYR_APP}"
```

### Customer kas config

```yaml
header:
  version: 11

includes:
  - repo: meta-pantavisor
    file: kas/snippets/pvcm-mcu.yml

local_conf_fragment: |
  MCU_MACHINE      = "imx8mn-var-som-m7"
  MCU_ZEPHYR_BOARD = "imx8mn_evk/mimx8mn6/m7"
  MCU_ZEPHYR_APP   = "path/to/customer/zephyr/app"
```

---

## Implementation Phases

### Phase 1 -- Foundation

Primary goal: validate the full stack end-to-end with minimal scope.
Demonstrates that an M core / external MCU can be a Pantavisor container
with revision state queries and health monitoring working.

- `protocol/pvcm_protocol.h` -- canonical wire format, all opcodes
- Zephyr SDK: `pvcm_server`, `pvcm_heartbeat`, `pvcm_state`, `pvcm_log_backend`
- FreeRTOS SDK: same mandatory modules with FreeRTOS primitives
- pvcm-manager: probe, UART + RPMsg transport, health monitoring, log forwarding
- Bootstate abstraction refactor in Pantavisor (pluggable backend)
- **Demo:** Zephyr shell on i.MX8MN M7 -- `pv status`, `pv containers`,
  `pv get /api/v1/state` over ttyRPMSG
- **Demo:** RP2040 Pico via USB UART as external MCU on any Linux SBC

### Phase 2 -- Full OTA Coupling

Primary goal: complete revision lifecycle including MCU firmware update,
bidirectional rollback, and U-Boot integration.

- MCU firmware update protocol (PVCM_FW_UPDATE_START/DATA/END)
- U-Boot PVCM client (board_late_init MCU query)
- Zero-config onboarding: virgin MCU detection and state migration
- Bidirectional rollback: MCU crash loops trigger Linux rollback
- MCU health policy: tryboot phase (zero tolerance) vs operational (resilient)
- meta-pantavisor: kas snippet, Zephyr multiconfig, BSP bbappend
- Multi-MCU support: multiple containers, multiple UART/RPMsg channels

### Phase 3 -- Service Mesh and Display

Primary goal: MCU as full peer in xconnect service mesh with REST and DBus
gateway, plus display frontend capability.

- MCU services.json / run.json model in Pantavisor
- pvcm-manager xconnect-graph integration and bridge reconciliation
- REST gateway: container service consumption from MCU firmware
- DBus gateway Tier 1: message assembly SDK (see pvcm-dbus.md)
- DBus gateway Tier 2: catalog REST wrapper containers (NM, BlueZ, ModemManager)
- MCU DBus service exposure on Linux system bus
- LVGL display frontend framework for Zephyr
- LCDIF layer ownership model: M7 as permanent display frontend
- Pantavisor dashboard demo: live revision/container state on M7 display
- Multi-Pico demo: 4x RP2040 as separate MCU containers
