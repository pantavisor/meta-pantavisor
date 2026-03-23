# PVCM Protocol -- Summary

PVCM (Pantavisor Container MCU) is the binary protocol between
`pvcm-manager` (Linux daemon on A53) and RTOS firmware running on an MCU
(external via UART, or internal M core via RPMsg).

---

## Transport

Two physical transports, identical wire format:

```
UART:   sync bytes + length framing, stream reassembly on Linux side
RPMsg:  same framing, kernel handles message boundaries
```

All traffic is fully multiplexed -- firmware update chunks, heartbeats,
REST calls, DBus signals, and log lines all flow on the same connection
simultaneously. No special modes, no channel switching.

---

## Frame Format

```
[ 0xAA | 0x55 | len 2B LE | payload | crc32 4B LE ]
```

- `0xAA 0x55` -- sync bytes
- `len` -- payload length in bytes (little-endian uint16)
- `payload` -- starts with 1-byte opcode, followed by opcode-specific fields
- `crc32` -- CRC32 of payload only (not sync bytes or length)

---

## Opcode Table

```c
typedef enum {

    /* --- Handshake --- */
    PVCM_OP_HELLO               = 0x01,  /* Linux -> MCU: probe */
    PVCM_OP_HELLO_RESP          = 0x02,  /* MCU -> Linux: I am here, protocol version */

    /* --- Boot State --- */
    /* Linux (or U-Boot) queries MCU for revision boot state */
    PVCM_OP_QUERY_STATE         = 0x03,  /* Linux -> MCU */
    PVCM_OP_STATE_RESP          = 0x04,  /* MCU -> Linux: full boot state */

    /* --- Revision Lifecycle --- */
    /* Maps directly to Pantavisor pv_try / pv_trying / pv_rev semantics */
    PVCM_OP_SET_TRYBOOT         = 0x05,  /* Linux -> MCU: stage new revision for tryboot */
    PVCM_OP_COMMIT              = 0x06,  /* Linux -> MCU: commit running revision as stable */
    PVCM_OP_ROLLBACK            = 0x07,  /* Linux -> MCU: explicit rollback to stable */
    PVCM_OP_ACK                 = 0x08,  /* MCU -> Linux: command accepted */
    PVCM_OP_NACK                = 0x09,  /* MCU -> Linux: command rejected, error code */

    /* --- Health Events (MCU -> Linux, unsolicited) --- */
    PVCM_EVT_HEARTBEAT          = 0x10,  /* every 5s: uptime, crash_count, health status */
    PVCM_EVT_BRIDGE_READY       = 0x11,  /* MCU gateway is up and ready */
    PVCM_EVT_BRIDGE_LOST        = 0x12,  /* MCU gateway went down */
    PVCM_EVT_SERVICE_LIST       = 0x13,  /* MCU reports its available services */
    PVCM_EVT_REVISION_CHANGE    = 0x14,  /* MCU noticed revision changed */
    PVCM_OP_REQUEST_ROLLBACK    = 0x15,  /* MCU requests Linux trigger rollback */

    /* --- Firmware Update (fully multiplexed, no special mode) --- */
    PVCM_OP_FW_UPDATE_START     = 0x20,  /* Linux -> MCU: start upload, sends total size + SHA256 */
    PVCM_OP_FW_UPDATE_DATA      = 0x21,  /* Linux -> MCU: one 512-byte chunk */
    PVCM_OP_FW_UPDATE_END       = 0x22,  /* Linux -> MCU: upload done, MCU verifies SHA256 */
    PVCM_EVT_FW_PROGRESS        = 0x23,  /* MCU -> Linux: progress % after each chunk ACK */

    /* --- Log Stream --- */
    PVCM_OP_LOG                 = 0x28,  /* MCU -> Linux: log line -> PV log server */

    /* --- MCU Detection --- */
    PVCM_OP_SMP_REJECT          = 0x29,  /* MCU -> Linux: I speak PVCM not SMP */

    /* --- REST Gateway --- */
    /* MCU as client: calls REST APIs exposed by Linux containers */
    PVCM_OP_REST_REQ            = 0x30,  /* MCU -> Linux: outbound REST request */
    PVCM_OP_REST_RESP           = 0x31,  /* Linux -> MCU: outbound REST response */
    /* MCU as server: Linux containers call REST APIs exposed by MCU */
    PVCM_OP_REST_INVOKE         = 0x32,  /* Linux -> MCU: inbound REST request */
    PVCM_OP_REST_INVOKE_RESP    = 0x33,  /* MCU -> Linux: inbound REST response */

    /* --- DBus Gateway --- */
    /* MCU calls Linux DBus services; Linux can also call into MCU */
    PVCM_OP_DBUS_CALL           = 0x40,  /* MCU -> Linux: call a DBus method */
    PVCM_OP_DBUS_CALL_RESP      = 0x41,  /* Linux -> MCU: DBus method reply */
    PVCM_OP_DBUS_SUBSCRIBE      = 0x42,  /* MCU -> Linux: subscribe to a DBus signal */
    PVCM_OP_DBUS_UNSUBSCRIBE    = 0x43,  /* MCU -> Linux: cancel subscription */
    PVCM_OP_DBUS_SIGNAL         = 0x44,  /* Linux -> MCU: subscribed signal fired */
    PVCM_OP_DBUS_EXPOSE         = 0x45,  /* MCU -> Linux: register MCU as DBus service */
    PVCM_OP_DBUS_INVOKE         = 0x46,  /* Linux -> MCU: call MCU-exposed endpoint */
    PVCM_OP_DBUS_INVOKE_RESP    = 0x47,  /* MCU -> Linux: response to invoke */

} pvcm_op_t;
```

---

## Key Structs

```c
/* HELLO_RESP -- MCU identifies itself */
typedef struct {
    uint8_t  op;
    uint8_t  protocol_version;  /* current: 1 */
    uint32_t baudrate;          /* MCU's configured UART baudrate */
    uint16_t max_msg_size;
    uint8_t  mcu_fw_version;
    uint32_t crc32;
} __packed pvcm_hello_resp_t;

/* STATE_RESP -- complete boot state, answers all Linux/U-Boot questions */
typedef struct {
    uint8_t  op;
    uint8_t  status;
    uint8_t  stable_slot;       /* 0=A 1=B */
    uint8_t  tryboot_slot;
    uint8_t  tryboot_pending;   /* new revision staged, not yet attempted */
    uint8_t  tryboot_trying;    /* set atomically BEFORE booting tryboot partition
                                   cleared only on COMMIT
                                   if set on boot = last tryboot failed -> rollback */
    uint32_t stable_rev;
    uint32_t tryboot_rev;
    uint8_t  mcu_fw_version;
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_state_resp_t;

/* HEARTBEAT -- pushed every 5s automatically, zero app code required */
typedef struct {
    uint8_t  op;
    uint8_t  status;            /* 0=OK 1=DEGRADED */
    uint16_t uptime_s;
    uint8_t  crash_count;       /* reset on COMMIT, incremented in Reset_Handler */
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_heartbeat_t;

/* LOG -- MCU log line forwarded to Pantavisor log server */
typedef struct {
    uint8_t  op;
    uint8_t  level;             /* 0=ERR 1=WRN 2=INF 3=DBG */
    uint16_t msg_len;
    char     module[16];        /* source module name */
    char     msg[224];
    uint32_t crc32;
} __packed pvcm_log_t;

/* REST_REQ -- MCU calls a Linux container REST API */
typedef struct {
    uint8_t  op;
    uint8_t  req_id;            /* correlates with REST_RESP */
    uint8_t  method;            /* 0=GET 1=POST 2=PUT 3=DELETE */
    uint8_t  reserved;
    char     path[60];
    char     body[192];
    uint32_t crc32;
} __packed pvcm_rest_req_t;

/* REST_RESP */
typedef struct {
    uint8_t  op;
    uint8_t  req_id;
    uint16_t status_code;       /* HTTP-style: 200, 404, 500 etc */
    char     body[248];
    uint32_t crc32;
} __packed pvcm_rest_resp_t;

/* REST_INVOKE -- Linux calls a REST endpoint exposed by MCU */
typedef struct {
    uint8_t  op;
    uint8_t  invoke_id;         /* correlates with REST_INVOKE_RESP */
    uint8_t  method;            /* 0=GET 1=POST 2=PUT 3=DELETE */
    uint8_t  reserved;
    char     path[60];          /* registered endpoint path */
    char     body[192];
    uint32_t crc32;
} __packed pvcm_rest_invoke_t;

/* REST_INVOKE_RESP -- MCU responds to inbound REST call */
typedef struct {
    uint8_t  op;
    uint8_t  invoke_id;
    uint16_t status_code;       /* HTTP-style: 200, 404, 500 etc */
    char     body[248];
    uint32_t crc32;
} __packed pvcm_rest_invoke_resp_t;

/* DBUS_CALL -- MCU calls a DBus method via Linux gateway */
typedef struct {
    uint8_t  op;
    uint8_t  req_id;
    char     path[60];          /* e.g. /network/connect */
    char     args[188];         /* JSON-encoded args */
    uint32_t crc32;
} __packed pvcm_dbus_call_t;

/* DBUS_SUBSCRIBE -- MCU subscribes to a DBus signal */
typedef struct {
    uint8_t  op;
    uint8_t  sub_id;
    char     path[60];          /* e.g. /network/state */
    uint32_t crc32;
} __packed pvcm_dbus_sub_t;

/* DBUS_SIGNAL -- Linux pushes fired signal to MCU */
typedef struct {
    uint8_t  op;
    uint8_t  sub_id;            /* matches subscription */
    uint16_t payload_len;
    char     payload[248];      /* JSON signal data */
    uint32_t crc32;
} __packed pvcm_dbus_signal_t;

/* DBUS_EXPOSE -- MCU registers itself as a DBus service endpoint */
typedef struct {
    uint8_t  op;
    uint8_t  endpoint_id;
    char     path[60];          /* e.g. /sensor/temperature */
    uint32_t crc32;
} __packed pvcm_dbus_expose_t;

/* DBUS_INVOKE -- Linux calls into MCU-exposed endpoint */
typedef struct {
    uint8_t  op;
    uint8_t  invoke_id;
    uint8_t  endpoint_id;
    uint8_t  reserved;
    char     args[248];
    uint32_t crc32;
} __packed pvcm_dbus_invoke_t;

/* FW_UPDATE_START -- begin streaming firmware to inactive MCUboot slot */
typedef struct {
    uint8_t  op;
    uint8_t  slot;              /* 1 = MCUboot secondary slot */
    uint32_t total_size;
    uint32_t chunk_size;        /* 512 bytes recommended */
    uint8_t  sha256[32];        /* SHA256 of complete firmware image */
    uint32_t crc32;
} __packed pvcm_fw_start_t;

/* FW_UPDATE_DATA -- one chunk (request/response per chunk) */
typedef struct {
    uint8_t  op;
    uint8_t  reserved;
    uint16_t seq;               /* sequence number */
    uint32_t offset;            /* byte offset in image */
    uint16_t len;               /* bytes in this chunk */
    uint8_t  data[512];
    uint32_t crc32;
} __packed pvcm_fw_data_t;

/* FW_UPDATE_END -- all chunks sent, MCU verifies SHA256 */
typedef struct {
    uint8_t  op;
    uint8_t  reserved[3];
    uint32_t crc32;
} __packed pvcm_fw_end_t;

/* EVT_FW_PROGRESS -- pushed by MCU after each chunk ACK */
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

Persistent state stored in MCU internal flash. Maps directly to
Pantavisor's existing `uboot.txt` + U-Boot env boot state semantics.

```c
typedef struct {
    uint32_t magic;             /* 0x5056434D "PVCM" */
    uint32_t version;

    uint32_t stable_rev;        /* equiv: pv_rev in uboot.txt */
    uint8_t  stable_slot;       /* 0=A 1=B */
    uint32_t tryboot_rev;       /* equiv: pv_try in uboot.txt */
    uint8_t  tryboot_slot;
    uint8_t  tryboot_pending;   /* pv_try is set, tryboot not yet attempted */
    uint8_t  tryboot_trying;    /* set BEFORE jumping to tryboot partition
                                   cleared only on COMMIT
                                   persistent: survives warm reset, power loss
                                   if set on boot = tryboot failed -> rollback */
    uint8_t  crash_count;       /* incremented in MCU Reset_Handler
                                   reset to 0 on COMMIT */
    uint8_t  crash_threshold;   /* if crash_count >= threshold during tryboot
                                   MCU self-rolls back in Reset_Handler */
    uint32_t crc32;
} pvcm_flash_state_t;
```

### tryboot_trying -- The Critical Field

```
Linux stages tryboot:
  sends SET_TRYBOOT
  MCU writes tryboot_pending=1, tryboot_trying=0 to flash

U-Boot queries MCU (QUERY_STATE):
  MCU atomically: tryboot_pending=0, tryboot_trying=1, writes flash
  THEN sends STATE_RESP
  --> flash committed before U-Boot boots kernel
  --> any reset now leaves tryboot_trying=1

On next boot if tryboot_trying=1:
  U-Boot sees uncommitted tryboot -> boots stable, sends ROLLBACK

Healthy boot, Linux commits (COMMIT):
  MCU writes stable_rev = tryboot_rev
  tryboot_trying=0, tryboot_pending=0, crash_count=0
```

---

## Typical Message Flows

### Startup / Probe

```
pvcm-manager -> MCU:  HELLO
MCU -> pvcm-manager:  HELLO_RESP  { protocol_version=1, baudrate=921600 }

pvcm-manager -> MCU:  QUERY_STATE
MCU -> pvcm-manager:  STATE_RESP  { stable_rev=42, stable_slot=A,
                                     tryboot_pending=0, tryboot_trying=0 }
```

If no PVCM response, pvcm-manager tries SMP echo. If SMP responds with
`hash: Unavailable` -> MCUboot with no firmware, install needed.
MCU responding to PVCM can reject SMP probes with `PVCM_OP_SMP_REJECT`.

### Normal Operation

```
MCU -> pvcm-manager:  EVT_HEARTBEAT  { status=OK, uptime=3600, crash_count=0 }
                      (every 5 seconds, automatic, zero app code)

MCU -> pvcm-manager:  LOG  { level=INF, module="sensor", msg="temp=22.4C" }
                      (forwarded to Pantavisor log server)

MCU -> pvcm-manager:  REST_REQ  { req_id=1, GET, path="/sensor/config" }
pvcm-manager -> MCU:  REST_RESP { req_id=1, 200, body='{"interval":5}' }

MCU -> pvcm-manager:  DBUS_SUBSCRIBE  { sub_id=1, path="/network/state" }
pvcm-manager -> MCU:  ACK
...later...
pvcm-manager -> MCU:  DBUS_SIGNAL  { sub_id=1, payload='{"state":70}' }
```

### OTA Firmware Update (fully multiplexed)

```
pvcm-manager -> MCU:  FW_UPDATE_START { slot=1, size=245760, sha256=... }
MCU -> pvcm-manager:  ACK

pvcm-manager -> MCU:  FW_UPDATE_DATA  { seq=0, offset=0, len=512, data=[...] }
MCU -> pvcm-manager:  ACK
MCU -> pvcm-manager:  EVT_FW_PROGRESS { percent=0, bytes_written=512 }

-- other traffic continues interleaved --
MCU -> pvcm-manager:  EVT_HEARTBEAT   { status=OK }
MCU -> pvcm-manager:  REST_RESP       { req_id=7, 200, body="..." }

pvcm-manager -> MCU:  FW_UPDATE_DATA  { seq=1, offset=512, len=512, data=[...] }
MCU -> pvcm-manager:  ACK
MCU -> pvcm-manager:  EVT_FW_PROGRESS { percent=1, bytes_written=1024 }

... N chunks ...

pvcm-manager -> MCU:  FW_UPDATE_END
MCU -> pvcm-manager:  ACK  (SHA256 verified) or NACK (checksum failed)

pvcm-manager -> MCU:  SET_TRYBOOT
MCU -> pvcm-manager:  ACK
MCU calls boot_request_upgrade(BOOT_UPGRADE_TEST), reboots
MCUboot swaps slot 0 <-> slot 1, new firmware boots

pvcm-manager waits for HELLO + HEARTBEAT from new firmware
pvcm-manager -> MCU:  COMMIT
MCU calls boot_write_img_confirmed(), writes stable state to flash
MCU -> pvcm-manager:  ACK
```

If MCU crashes before COMMIT: MCUboot reverts to old slot on next reset.

### MCU Emergency Rollback

```
MCU detects fault during operation:
MCU -> pvcm-manager:  REQUEST_ROLLBACK
pvcm-manager triggers Pantavisor rollback for full Linux + MCU revision
```

---

## Detection and Initial Install

pvcm-manager probe sequence on startup:

```
1. Send PVCM HELLO
   -> PVCM response:  firmware running, normal operation

2. Send SMP echo (mcumgr framing)
   -> SMP response, image list hash=Unavailable:
      MCUboot running, slots empty, install needed
      install via FW_UPDATE_* after MCUboot is running
   -> SMP response, valid hash, bootable=true:
      PVCM firmware present but crashed before init
      send SMP reset, wait for PVCM HELLO

3. No response to either:
   -> MCU absent or unpowered
```

MCUboot SMP is only used for detection and the one-time initial install
from a virgin state. All subsequent OTA uses PVCM_FW_UPDATE_* natively.

---

## Health Policy

Two phases after a revision change:

```
TRYBOOT phase (between SET_TRYBOOT and COMMIT):
  zero tolerance
  any of: heartbeat missing, crash_count > 0, status=DEGRADED
  -> pvcm-manager triggers Pantavisor rollback immediately

COMMITTED phase (after COMMIT):
  resilient, like container restart policy
  heartbeat missing -> pvcm-manager asserts MCU reset GPIO
  crash_count high  -> pvcm-manager asserts MCU reset GPIO
  max restarts exceeded -> alert only, stay running
  MCU sends REQUEST_ROLLBACK -> trigger Linux rollback
```

---

## Default UART Baudrate

```
921600 baud  -- protocol constant, not a config value
               works on RP2040, STM32, nRF52, ESP32
               firmware transfer 256KB ~3 seconds
```

Both sides implement the same constant. No negotiation needed.
pvcm-manager does autobaud scan as fallback if default fails.
