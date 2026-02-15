# DevicePass CLI and Hub — Implementation Plan (v6)

## Overview

DevicePass gives IoT devices blockchain-native identity and enables guardians to manage them through natural language via AI CLI agents. The system has three components:

1. **`devicepass-cli` (device side, shell + C)** — Generate identity, get claimed, then `serve`: connect to hub, open tunnel, announce container specs, handle incoming requests. Tiny footprint (~2MB), runs on embedded Linux. Shell scripts for identity/onboard commands, C for the persistent `serve` daemon and crypto tools.

2. **`hub.devicepass.ai` (cloud, Go)** — Rendezvous point. Verifies device and guardian identity against chain. Maintains WebSocket tunnels. Aggregates container specs per guardian. Exposes a fleet API that any MCP-compatible AI agent can consume.

3. **`devicepass-cli guardian` (guardian side)** — Manage devices on-chain (claim, fund, transfer). `guardian talk` authenticates with hub and launches Claude Code or Gemini CLI with automatic tool access to the entire fleet.

## Architecture

```
┌─────────────────────┐         ┌────────────────────────────┐
│  Device              │         │  hub.devicepass.ai (Go)    │
│                      │         │                            │
│  devicepass-cli      │         │  ┌──────────────────────┐  │
│    init   (shell)    │         │  │ Per-guardian state    │  │
│    onboard (shell)   │         │  │                      │  │
│    serve   (C)       │         │  │ devices: [...]       │  │
│      • auth (dev key)──────────│──│ container_types: {}  │  │
│      • open tunnel   │   WS   │  │ specs (aggregated)   │  │
│      • push specs    │         │  └──────────┬───────────┘  │
│      • push metadata │         │             │              │
│      • heartbeat     │         │  Guardian Fleet API        │
│      • handle reqs   │         │    GET  /devices           │
│                      │         │    GET  /containers/X/api  │
│  Containers:         │         │    POST /devices/X/call    │
│    system            │         │    POST /devices/X/meta    │
│    node-red          │         │    POST /devices/group/call│
│    mosquitto         │         │    GET  /openapi.json      │
│    sensors           │         └────────────┬───────────────┘
└─────────────────────┘                      │
                                             │ standard OpenAPI
                                             │
                                ┌────────────▼───────────────┐
                                │  Guardian                   │
                                │                             │
                                │  devicepass-cli guardian     │
                                │    claim / fund / transfer  │
                                │    talk --ai claude|gemini  │
                                │      ↓                      │
                                │    mcp-openapi-proxy        │
                                │      → hub fleet API        │
                                │      ↓                      │
                                │    Claude Code / Gemini CLI │
                                │                             │
                                │  "restart mosquitto on the  │
                                │   garage and show me all    │
                                │   connected clients"        │
                                └─────────────────────────────┘
```

---

## Part 1: Device Side — `devicepass-cli`

### Dependencies

| Tool | Size | Purpose |
|------|------|---------|
| busybox (sh/ash) | (base) | Shell, coreutils |
| openssl / libcrypto | ~1.5MB | secp256k1 key gen, TLS, ECDSA |
| jq | ~50KB | JSON construction (shell commands) |
| keccak256sum | ~20KB | Address derivation, message hashing (C) |
| ethsign | ~25KB | Ethereum ECDSA signatures (C) |
| devicepass-serve | ~100KB | Hub connection, tunnel, spec push (C) |

Optional: qrencode (~30KB). **Total: ~2MB.**

`devicepass-serve` is the C binary for the `serve` subcommand. Links against libcrypto (already present for openssl) and uses either libwebsockets or a minimal built-in WebSocket client over TLS for the hub connection. No Go, no curl dependency.

### Bundled C Tools

**keccak256sum** — Self-contained ~250 lines, ~17KB static. Keccak-256 (NOT NIST SHA-3). Test vectors verified.

**ethsign** — Wraps libcrypto, ~200 lines, ~25KB. Signs 32-byte hash, outputs 65-byte Ethereum signature (r,s,v).

### Commands

#### `devicepass-cli init`

Generate device identity. Fully offline.

1. Generate secp256k1 keypair via openssl
2. Derive Ethereum address via keccak256sum
3. Save: device.key (chmod 600), device.address, device.id

```
$ devicepass-cli init

Generating device identity (secp256k1)...
  Address:   0x304e9fd701df6440af7d9b114e0d5f4df7426e77
  Device ID: dp-304e9fd701df
  Key:       /var/lib/devicepass/device.key

Run: devicepass-cli onboard
```

Flags: `--force` (regenerate)

#### `devicepass-cli onboard`

Sign claim blob and output it. Fully offline on device side.

1. Ensure identity exists (auto-init if not)
2. Generate nonce (timestamp)
3. Sign: keccak256(prefix + keccak256(abi.encodePacked(addr, nonce, chain_id)))
4. Build claim blob JSON
5. Output: QR (interactive), JSON (quiet), or file (--out)

```
$ devicepass-cli onboard --quiet
{"version":1,"device":"0x304e...","nonce":1739612345,"chain_id":8453,"contract":"0x1234...","signature":"0x3a4b..."}
```

Flags: `--chain-id`, `--contract`, `--out FILE`, `--quiet`, `--non-interactive`

#### `devicepass-cli status`

Show device state from local files and optionally query chain/hub.

```
$ devicepass-cli status

Device:    dp-304e9fd701df
Address:   0x304e9fd701df6440af7d9b114e0d5f4df7426e77
Guardian:  0x7a3f...2b1e (on-chain)
Hub:       connected (uptime: 4h 23m)
Tunnel:    open
Specs:     3 containers announced
  system     4 endpoints
  node-red   5 endpoints
  mosquitto  3 endpoints
Metadata:  name=living-room
```

Flags: `--verify` (query chain), `--json`

When `devicepass-cli serve` is running, `status` reads from its state (shared file or socket). Otherwise shows local identity files only.

#### `devicepass-cli export-key`

Output raw hex private key for import into MetaMask, cast, or any Ethereum wallet.

Flags: `--raw` (hex only, no warnings)

### `devicepass-cli serve` — Device Runtime (C)

**The persistent operational mode.** After claiming, this is what runs forever. Connects to hub, opens tunnel, announces container specs, handles incoming requests. Started by the init system (Pantavisor, systemd, or container entrypoint). The `pv-devicepass` Pantavisor app uses `devicepass-cli serve` as its entrypoint.

Written in C for minimal footprint and consistency with the other device-side tools. Links against libcrypto (shared with openssl/ethsign) and either libwebsockets or a minimal built-in WebSocket-over-TLS client.

```
$ devicepass-cli serve

[devicepass] identity:    dp-304e9fd701df (0x304e...)
[devicepass] passport:    verified (guardian: 0x7a3f...2b1e)
[devicepass] hub:         connecting to api.devicepass.ai...
[devicepass] auth:        challenge signed, verified
[devicepass] tunnel:      open
[devicepass] specs:       pushed 3 containers (12 endpoints)
[devicepass]   system:    4 endpoints
[devicepass]   node-red:  5 endpoints  
[devicepass]   mosquitto: 3 endpoints
[devicepass] metadata:    name=living-room
[devicepass] ready, waiting for requests...
```

**Startup flow:**

```
1. Load device identity from /var/lib/devicepass/ (address, key)
2. Verify passport exists on-chain (optional, configurable)
3. Connect WebSocket: wss://api.devicepass.ai/v1/device/connect
4. Authenticate: sign challenge from hub with device key (via libcrypto)
5. Hub verifies signature, checks chain for passport
6. Push metadata to hub (device name, labels, hardware info)
7. Collect container specs from /var/lib/devicepass/specs/*.json
8. Push specs to hub over the WebSocket
9. Enter main loop (epoll/select):
   a. Heartbeat every 30s
   b. Watch /var/lib/devicepass/specs/ for changes (inotify)
   c. On spec change: re-push specs to hub
   d. Watch /var/lib/devicepass/meta.json for changes (inotify)
   e. On metadata change: re-push metadata to hub
   f. Handle incoming tunnel requests (HTTP-over-WebSocket)
   g. Reconnect with exponential backoff on disconnect
```

**Spec collection:**

Each container drops an OpenAPI spec fragment at a well-known path:

```
/var/lib/devicepass/specs/system.json
/var/lib/devicepass/specs/node-red.json
/var/lib/devicepass/specs/mosquitto.json
```

These are standard OpenAPI 3.x specs describing that container's HTTP endpoints. `serve` reads them all, bundles them, and pushes to hub on connect and on change.

Example: `/var/lib/devicepass/specs/mosquitto.json`

```json
{
  "openapi": "3.0.3",
  "info": {"title": "Mosquitto MQTT Broker", "version": "2.0.18"},
  "paths": {
    "/mosquitto/status": {
      "get": {
        "summary": "Broker status, uptime, message stats",
        "operationId": "broker_status",
        "responses": {"200": {"description": "Broker status JSON"}}
      }
    },
    "/mosquitto/clients": {
      "get": {
        "summary": "List connected MQTT clients",
        "operationId": "connected_clients",
        "responses": {"200": {"description": "Client list"}}
      }
    }
  }
}
```

**Device metadata:**

The device maintains a metadata file that `serve` pushes to hub:

```
/var/lib/devicepass/meta.json
```

```json
{
  "name": "living-room",
  "labels": {"location": "floor-1", "role": "home-automation"},
  "hardware": {"board": "rpi4", "arch": "aarch64", "memory_mb": 4096}
}
```

Guardians can set the device name via the hub fleet API (`POST /devices/{id}/meta`), which the hub routes through the tunnel. `serve` receives it, updates `meta.json`, and pushes the updated metadata back to hub. The name lives on the device — the hub just reflects what the device reports.

**Incoming tunnel requests (HTTP-over-WebSocket):**

When the hub routes a guardian's API call to this device, `serve` receives it as a JSON envelope over the WebSocket and proxies to the correct local container:

```json
// Incoming (hub → device via WebSocket)
{
  "id": "req-a1b2c3",
  "type": "http",
  "method": "POST",
  "path": "/node-red/flows",
  "headers": {"Content-Type": "application/json"},
  "body": "{\"flows\":[...]}"
}

// Outgoing (device → hub via WebSocket)
{
  "id": "req-a1b2c3",
  "type": "http_response",
  "status": 200,
  "headers": {"Content-Type": "application/json"},
  "body": "{\"success\":true}"
}
```

The `id` field correlates request/response (multiple requests can be in-flight concurrently). The first path segment identifies the container — `serve` looks up the local port from container metadata and proxies the HTTP call.

For the metadata endpoint, `serve` handles it directly:

```json
// Set device name (hub → device)
{"id": "req-x1", "type": "http", "method": "POST", "path": "/_meta",
 "body": "{\"name\":\"living-room\",\"labels\":{\"location\":\"floor-1\"}}"}

// serve writes meta.json, pushes update to hub, responds
{"id": "req-x1", "type": "http_response", "status": 200,
 "body": "{\"updated\":true}"}
```

**Configuration:**

```
/etc/devicepass.conf (or environment variables)

DEVICEPASS_HUB_URL=wss://api.devicepass.ai/v1/device/connect
DEVICEPASS_RPC=https://mainnet.base.org
DEVICEPASS_SPEC_DIR=/var/lib/devicepass/specs
DEVICEPASS_META_FILE=/var/lib/devicepass/meta.json
DEVICEPASS_IDENTITY_DIR=/var/lib/devicepass
```

### File Layout (Device)

```
devicepass-cli/
├── bin/
│   └── devicepass-cli               # Main entry point / dispatcher (shell)
├── lib/
│   ├── config.sh                    # Paths, defaults, dep checks
│   ├── display.sh                   # Logging, colors, output helpers
│   ├── identity.sh                  # Key gen, address derivation
│   ├── signing.sh                   # Claim message construction + signing
│   └── guardian/                    # Guardian subcommands (see Part 3)
├── tools/
│   ├── keccak256sum.c               # Ethereum Keccak-256 (~250 lines)
│   ├── ethsign.c                    # ECDSA secp256k1 signing (~200 lines)
│   ├── serve.c                      # Hub connection, tunnel, specs, meta
│   ├── ws.c / ws.h                  # WebSocket-over-TLS client
│   ├── json.c / json.h              # Minimal JSON parser/builder
│   └── Makefile
└── README.md

Runtime data: /var/lib/devicepass/ (chmod 700)
├── device.key                       # secp256k1 private key (chmod 600)
├── device.pub.hex                   # Public key hex, no 04 prefix
├── device.address                   # Ethereum address (0x...)
├── device.id                        # Short ID (dp-XXXXXXXXXXXX)
├── claim.json                       # Signed claim blob (if pending)
├── passport.json                    # On-chain passport reference
├── meta.json                        # Device name, labels, hardware info
└── specs/                           # Container OpenAPI specs
    ├── system.json
    ├── node-red.json
    └── mosquitto.json
```

### Implementation Order (Device)

1. `keccak256sum.c` — build, test vectors ✓ (done)
2. `ethsign.c` — build, test against known Ethereum signatures
3. `lib/display.sh`, `lib/config.sh` — helpers
4. `lib/identity.sh` + `init` command
5. `lib/signing.sh` + `onboard` command
6. `export-key` command
7. `status` command (local only)
8. `tools/serve.c` + `serve` command — hub connection, auth, tunnel, spec push, metadata push (C)

---

## Part 2: Hub Side — `hub.devicepass.ai` (Go)

The hub is the rendezvous and fleet intelligence layer. It verifies identities against the chain, maintains device tunnels, aggregates container specs, and exposes a fleet API for guardians. Written in Go for strong WebSocket/concurrency support.

### Hub Responsibilities

1. **Device connections** — Accept websocket connections from devices, verify device identity (signature + on-chain passport), maintain tunnels.

2. **Spec aggregation** — Receive OpenAPI specs from devices on connect and on change. Deduplicate by container type. Maintain per-guardian fleet state.

3. **Guardian authentication** — Challenge-response with guardian key, verify against chain (PassportCreated events).

4. **Fleet API** — Expose a guardian-scoped REST API with OpenAPI spec. This is what `mcp-openapi-proxy` talks to.

5. **Request routing** — Route guardian API calls to the correct device through the tunnel.

### Device Connection Protocol

```
Device (devicepass-cli serve)          Hub
  │                                        │
  │  WSS /v1/device/connect                │
  │  {address: "0x304e..."}                │
  │ ─────────────────────────────────────> │
  │                                        │
  │  {challenge: "nonce-abc"}              │
  │ <───────────────────────────────────── │
  │                                        │
  │  {signature: "0x..."}                  │
  │ ─────────────────────────────────────> │
  │                                        │  Verify sig
  │                                        │  Check chain: passport exists?
  │                                        │  Look up guardian for this device
  │                                        │
  │  {authenticated: true,                 │
  │   guardian: "0x7a3f..."}               │
  │ <───────────────────────────────────── │
  │                                        │
  │  Push metadata:                        │
  │  {type: "meta",                        │
  │   name: "living-room",                 │
  │   labels: {"location": "floor-1"},     │
  │   hardware: {"board": "rpi4"}}         │
  │ ─────────────────────────────────────> │
  │                                        │  Update device metadata
  │                                        │
  │  Push specs:                           │
  │  {type: "specs",                       │
  │   containers: [                        │
  │     {name: "system", spec: {...}},     │
  │     {name: "node-red", spec: {...}},   │
  │     {name: "mosquitto", spec: {...}}   │
  │   ]}                                   │
  │ ─────────────────────────────────────> │
  │                                        │  Update guardian fleet state
  │                                        │  Deduplicate container specs
  │                                        │
  │  (tunnel open, heartbeat every 30s)    │
  │ <────────────────────────────────────> │
  │                                        │
  │  On spec change:                       │
  │  {type: "specs", containers: [...]}    │
  │ ─────────────────────────────────────> │
  │                                        │  Update fleet state
  │                                        │
  │  On metadata change:                   │
  │  {type: "meta", name: "...", ...}      │
  │ ─────────────────────────────────────> │
  │                                        │  Update device metadata
```

### Tunnel Protocol — HTTP-over-WebSocket

The same WebSocket used for auth/specs/heartbeat also carries tunneled HTTP requests. Each message is a JSON envelope with a correlation ID for concurrent request/response multiplexing:

```json
// Request (hub → device)
{
  "id": "req-a1b2c3",
  "type": "http",
  "method": "POST",
  "path": "/node-red/flows",
  "headers": {"Content-Type": "application/json"},
  "body": "{\"flows\":[...]}"
}

// Response (device → hub)  
{
  "id": "req-a1b2c3",
  "type": "http_response",
  "status": 200,
  "headers": {"Content-Type": "application/json"},
  "body": "{\"success\":true}"
}
```

**Message types on the WebSocket:**

| type | direction | purpose |
|------|-----------|---------|
| `auth_challenge` | hub → device | Challenge nonce |
| `auth_response` | device → hub | Signed challenge |
| `auth_result` | hub → device | Success/failure |
| `meta` | device → hub | Device metadata (name, labels, hardware) |
| `specs` | device → hub | Container OpenAPI specs |
| `heartbeat` | both | Keep-alive (every 30s) |
| `http` | hub → device | Tunneled HTTP request |
| `http_response` | device → hub | Tunneled HTTP response |

**Body encoding:** For JSON payloads, `body` is a string (JSON-in-JSON). For binary payloads (future: firmware uploads, log downloads), `body` is base64-encoded with a `"body_encoding": "base64"` field. MVP: JSON only, 1MB size limit per message.

### Guardian Authentication

```
Guardian                                  Hub
  │                                        │
  │  POST /v1/guardian/auth                │
  │  {address: "0x7a3f..."}               │
  │ ─────────────────────────────────────> │
  │                                        │
  │  {challenge: "nonce-xyz"}              │
  │ <───────────────────────────────────── │
  │                                        │
  │  Sign with cast wallet sign            │
  │                                        │
  │  POST /v1/guardian/auth/verify         │
  │  {address, challenge, signature}       │
  │ ─────────────────────────────────────> │
  │                                        │  Verify sig
  │                                        │  Check chain: guardian owns devices?
  │                                        │
  │  {token: "jwt...",                     │
  │   expires: "2026-02-16T..."}           │
  │ <───────────────────────────────────── │
```

Token is a JWT or similar bearer token, scoped to this guardian's devices. Used for all subsequent fleet API calls.

### Per-Guardian Fleet State

The hub maintains in-memory (backed by DB) state per guardian:

```
guardian_state[0x7a3f...] = {
  devices: {
    "0x304e...": {
      short_id: "dp-304e9fd701df",
      name: "living-room",          # from device metadata push
      labels: {"location": "floor-1", "role": "home-automation"},
      hardware: {"board": "rpi4", "arch": "aarch64"},
      online: true,
      connected_since: "2026-02-15T08:00:00Z",
      last_heartbeat: "2026-02-15T12:30:00Z",
      containers: ["system", "node-red", "mosquitto"],
      tunnel: <websocket_ref>
    },
    "0x8b2a...": {
      short_id: "dp-8b2a1c5ef903",
      name: "garage",
      labels: {"location": "garage"},
      online: true,
      containers: ["system", "mosquitto", "sensors"],
      tunnel: <websocket_ref>
    },
    "0xf1c9...": {
      short_id: "dp-f1c9d0003b72",
      name: "office",
      online: false,
      last_seen: "2026-02-14T22:00:00Z",
      containers: ["system", "mosquitto"]     # from last connection
    }
  },
  container_types: {
    "system":    {spec: <OpenAPI JSON>, version: "1.0.0", devices: ["0x304e...", "0x8b2a..."]},
    "node-red":  {spec: <OpenAPI JSON>, version: "3.1.0", devices: ["0x304e..."]},
    "mosquitto": {spec: <OpenAPI JSON>, version: "2.0.18", devices: ["0x304e...", "0x8b2a..."]},
    "sensors":   {spec: <OpenAPI JSON>, version: "1.2.0", devices: ["0x8b2a..."]}
  }
}
```

**Spec deduplication:** Container specs are keyed by type name + version from `info.version` in the OpenAPI spec. When multiple devices push the same container type at the same version, one canonical spec is stored. If devices run different versions of the same container (e.g., mosquitto 2.0.18 vs 2.0.20), both specs are kept and tagged with which devices run which version. MVP: group by container name, track version. Later: expose version differences in the fleet API so the AI can report on version drift.

### Guardian Fleet API

All endpoints require `Authorization: Bearer <token>` from guardian auth.

#### `GET /v1/guardian/openapi.json`

**The key endpoint.** Returns a dynamically generated OpenAPI spec describing all available fleet operations, tailored to this guardian's current fleet state. This is what `mcp-openapi-proxy` points at.

The spec includes:
- `list_devices` operation
- `get_container_api` operation (parameterized by container type)
- `call_device` operation (parameterized by device + path)
- `call_devices` operation (group calls)
- Descriptions reference the guardian's actual device names and container types

```json
{
  "openapi": "3.0.3",
  "info": {
    "title": "DevicePass Fleet API",
    "description": "Manage your IoT device fleet. You have 3 devices (2 online).",
    "version": "1.0.0"
  },
  "servers": [{"url": "https://api.devicepass.ai/v1/guardian"}],
  "paths": {
    "/devices": {
      "get": {
        "operationId": "list_devices",
        "summary": "List all your devices with status, containers, and connectivity",
        "description": "Returns your device fleet. Currently: dp-304e (living-room, online), dp-8b2a (garage, online), dp-f1c9 (office, offline)."
      }
    },
    "/containers/{container_type}/api": {
      "get": {
        "operationId": "get_container_api",
        "summary": "Get the API spec for a container type",
        "description": "Returns the OpenAPI spec for a container type. Available types: system, node-red, mosquitto, sensors.",
        "parameters": [
          {"name": "container_type", "in": "path", "required": true,
           "schema": {"type": "string", "enum": ["system", "node-red", "mosquitto", "sensors"]}}
        ]
      }
    },
    "/devices/{device_id}/call": {
      "post": {
        "operationId": "call_device",
        "summary": "Call an API endpoint on a specific device",
        "description": "Routes request through tunnel to the device. Use get_container_api to discover available endpoints.",
        "parameters": [
          {"name": "device_id", "in": "path", "required": true,
           "schema": {"type": "string"},
           "description": "Device short ID (e.g. dp-304e) or full address"}
        ],
        "requestBody": {
          "content": {"application/json": {"schema": {
            "type": "object",
            "required": ["path", "method"],
            "properties": {
              "path": {"type": "string", "description": "Container endpoint path, e.g. /mosquitto/clients"},
              "method": {"type": "string", "enum": ["GET", "POST", "PUT", "DELETE"]},
              "body": {"type": "object", "description": "Request body for POST/PUT"}
            }
          }}}
        }
      }
    },
    "/devices/group/call": {
      "post": {
        "operationId": "call_devices",
        "summary": "Call an endpoint on multiple devices and get aggregated results",
        "description": "Fan-out request to multiple devices. Returns results keyed by device ID.",
        "requestBody": {
          "content": {"application/json": {"schema": {
            "type": "object",
            "required": ["devices", "path", "method"],
            "properties": {
              "devices": {"type": "array", "items": {"type": "string"},
                          "description": "Device IDs. Use 'all' for all online devices, 'container:mosquitto' for all devices running mosquitto, or 'label:location=floor-1' for label matching."},
              "path": {"type": "string"},
              "method": {"type": "string", "enum": ["GET", "POST", "PUT", "DELETE"]},
              "body": {"type": "object"}
            }
          }}}
        }
      }
    },
    "/devices/{device_id}/meta": {
      "post": {
        "operationId": "set_device_meta",
        "summary": "Set device name and labels",
        "description": "Sets human-readable name and labels on the device. Routed to device, stored locally, reflected back to hub.",
        "parameters": [
          {"name": "device_id", "in": "path", "required": true,
           "schema": {"type": "string"}}
        ],
        "requestBody": {
          "content": {"application/json": {"schema": {
            "type": "object",
            "properties": {
              "name": {"type": "string", "description": "Human-readable device name"},
              "labels": {"type": "object", "additionalProperties": {"type": "string"},
                         "description": "Key-value labels for grouping and filtering"}
            }
          }}}
        }
      }
    }
  }
}
```

**The spec is dynamic per guardian.** The descriptions mention their actual device names and available container types. This gives the AI excellent context without consuming tool slots.

#### `GET /v1/guardian/devices`

Returns device inventory with metadata.

```json
{
  "guardian": "0x7a3f...2b1e",
  "devices": [
    {
      "address": "0x304e...",
      "short_id": "dp-304e9fd701df",
      "name": "living-room",
      "labels": {"location": "floor-1", "role": "home-automation"},
      "hardware": {"board": "rpi4", "arch": "aarch64", "memory_mb": 4096},
      "online": true,
      "connected_since": "2026-02-15T08:00:00Z",
      "containers": [
        {"name": "system", "version": "1.0.0", "endpoints": 4},
        {"name": "node-red", "version": "3.1.0", "endpoints": 5},
        {"name": "mosquitto", "version": "2.0.18", "endpoints": 3}
      ]
    },
    {
      "address": "0x8b2a...",
      "short_id": "dp-8b2a1c5ef903",
      "name": "garage",
      "labels": {"location": "garage"},
      "hardware": {"board": "rpi4", "arch": "aarch64", "memory_mb": 2048},
      "online": true,
      "containers": [
        {"name": "system", "version": "1.0.0", "endpoints": 4},
        {"name": "mosquitto", "version": "2.0.18", "endpoints": 3},
        {"name": "sensors", "version": "1.2.0", "endpoints": 2}
      ]
    }
  ]
}
```

#### `GET /v1/guardian/containers/{type}/api`

Returns the OpenAPI spec for a container type. Fetched from the aggregated state — no tunnel call needed.

#### `POST /v1/guardian/devices/{id}/call`

Routes a request to a specific device through its tunnel.

```json
// Request
POST /v1/guardian/devices/dp-304e/call
{
  "path": "/mosquitto/clients",
  "method": "GET"
}

// Response (from device, via tunnel)
{
  "device": "dp-304e9fd701df",
  "status": 200,
  "data": {
    "clients": [
      {"id": "sensor-01", "connected": true, "subscriptions": 3},
      {"id": "logger-01", "connected": true, "subscriptions": 1}
    ]
  }
}
```

If the device is offline, returns immediately:

```json
{"error": "device_offline", "device": "dp-304e9fd701df", "last_seen": "2026-02-14T22:00:00Z"}
```

#### `POST /v1/guardian/devices/group/call`

Fan-out to multiple devices.

```json
// Request
POST /v1/guardian/devices/group/call
{
  "devices": ["container:mosquitto"],
  "path": "/mosquitto/clients",
  "method": "GET"
}

// Response (aggregated)
{
  "results": {
    "dp-304e9fd701df": {
      "status": 200,
      "data": {"clients": [...]}
    },
    "dp-8b2a1c5ef903": {
      "status": 200,
      "data": {"clients": [...]}
    }
  },
  "errors": {}
}
```

Device selectors:
- `["dp-304e", "dp-8b2a"]` — specific devices by short ID
- `["all"]` — all online devices
- `["container:mosquitto"]` — all online devices running mosquitto
- `["label:location=floor-1"]` — all online devices with matching label

#### `POST /v1/guardian/devices/{id}/meta`

Set device metadata (name, labels). Routed through the tunnel to the device — the device stores it locally and pushes the update back to hub.

```json
// Request
POST /v1/guardian/devices/dp-304e/meta
{
  "name": "living-room",
  "labels": {"location": "floor-1", "role": "home-automation"}
}

// Response
{
  "device": "dp-304e9fd701df",
  "updated": true,
  "meta": {
    "name": "living-room",
    "labels": {"location": "floor-1", "role": "home-automation"},
    "hardware": {"board": "rpi4", "arch": "aarch64", "memory_mb": 4096}
  }
}
```

The name and labels are guardian-settable. Hardware info is device-reported and read-only.

### Hub Implementation Notes

- **Language:** Go (gorilla/websocket or nhooyr/websocket + chi or echo for REST)
- **State:** In-memory with SQLite or Redis backing for persistence across restarts
- **Chain verification:** Call `passports(device)` on DevicePassRegistry via go-ethereum RPC at device connect and guardian auth. Cache results.
- **Token format:** JWT with guardian address, device list, expiry. Stateless verification via HMAC or Ed25519.
- **Tunnel transport:** HTTP-over-WebSocket (see Tunnel Protocol section). Request-response correlation via `id` field.
- **Spec storage:** Per-guardian aggregate rebuilt on device connect/disconnect/spec-change. Cached in memory, persisted for offline device history. Keyed by container type + version.
- **Metadata storage:** Device name, labels, hardware info stored per device. Guardian-settable (name, labels) via routed tunnel call. Device-reported (hardware) via metadata push.

---

## Part 3: Guardian Side — `devicepass-cli guardian`

### Dependencies

| Tool | Size | Purpose |
|------|------|---------|
| cast (Foundry) | ~50MB | TX construction, signing, chain queries |
| curl | ~250KB | Hub auth |
| jq | ~50KB | JSON parsing |
| claude or gemini | varies | AI CLI (user-installed, for `talk` only) |

### Management Commands

All wrap Foundry's `cast`. Common flags: `--rpc`, `--account`, `--contract`, `--json`.

| Command | Purpose |
|---------|---------|
| `guardian claim --blob FILE` | Submit claim blob to chain, become guardian |
| `guardian list` | List owned devices (from chain events) |
| `guardian status <DEVICE>` | On-chain passport + balance |
| `guardian fund <DEVICE> <AMOUNT>` | Send ETH to device wallet |
| `guardian balance <DEVICE>` | Check device wallet balance |
| `guardian transfer <DEVICE> <NEW>` | Transfer ownership |
| `guardian revoke <DEVICE>` | Deactivate passport |

### `devicepass-cli guardian talk`

Authenticate with hub, scaffold workspace, launch AI CLI. ~50 lines of shell.

```
$ devicepass-cli guardian talk --ai claude --account guardian

Authenticating with hub...                    ✓
  Guardian: 0x7a3f...2b1e (3 devices, 2 online)

Setting up workspace...
  /tmp/devicepass-talk-xK9m2/
  .mcp.json         ✓
  CLAUDE.md          ✓

Launching Claude Code...
```

**Implementation:**

```sh
#!/bin/sh
# guardian talk

AI="${1:-claude}"   # --ai claude|gemini

# 1. Authenticate with hub
GUARDIAN_ADDR=$(cast wallet address --account "$ACCOUNT")
CHALLENGE=$(curl -sf "$HUB_URL/v1/guardian/auth" \
  -d "{\"address\":\"$GUARDIAN_ADDR\"}" | jq -r '.challenge')
SIGNATURE=$(cast wallet sign "$CHALLENGE" --account "$ACCOUNT")
TOKEN=$(curl -sf "$HUB_URL/v1/guardian/auth/verify" \
  -d "{\"address\":\"$GUARDIAN_ADDR\",\"challenge\":\"$CHALLENGE\",\"signature\":\"$SIGNATURE\"}" \
  | jq -r '.token')

# 2. Fetch device summary for context file
DEVICES=$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "$HUB_URL/v1/guardian/devices")

# 3. Create temp workspace
WORKSPACE=$(mktemp -d /tmp/devicepass-talk-XXXX)
trap "rm -rf $WORKSPACE" EXIT

# 4. Write config
case "$AI" in
  claude)
    # .mcp.json — project-scoped MCP config for Claude Code
    cat > "$WORKSPACE/.mcp.json" << EOF
{
  "mcpServers": {
    "devicepass": {
      "command": "uvx",
      "args": ["mcp-openapi-proxy"],
      "env": {
        "OPENAPI_SPEC_URL": "${HUB_URL}/v1/guardian/openapi.json",
        "API_KEY": "$TOKEN",
        "API_AUTH_TYPE": "Bearer"
      }
    }
  }
}
EOF

    # CLAUDE.md — context for Claude Code
    cat > "$WORKSPACE/CLAUDE.md" << EOF
# DevicePass Guardian Session

You are managing IoT devices for this guardian.
Use the devicepass tools to query and control devices.

## Quick Reference
- list_devices: see all devices and their status
- get_container_api: learn what a container type can do
- call_device: execute an action on one device
- call_devices: execute on multiple devices at once

## Tips
- Always list_devices first to know what's online
- Use get_container_api to discover endpoints before calling them
- Device selectors: use short IDs (dp-304e), "all", or "container:mosquitto"
- Confirm destructive actions (restart, revoke) with the user
EOF
    ;;

  gemini)
    mkdir -p "$WORKSPACE/.gemini"
    cat > "$WORKSPACE/.gemini/settings.json" << EOF
{
  "mcpServers": {
    "devicepass": {
      "command": "uvx",
      "args": ["mcp-openapi-proxy"],
      "env": {
        "OPENAPI_SPEC_URL": "${HUB_URL}/v1/guardian/openapi.json",
        "API_KEY": "$TOKEN",
        "API_AUTH_TYPE": "Bearer"
      },
      "trust": true
    }
  }
}
EOF

    cat > "$WORKSPACE/GEMINI.md" << EOF
(same content as CLAUDE.md)
EOF
    ;;
esac

# 5. Launch
cd "$WORKSPACE"
exec "$AI"
```

**What the AI sees:**

The dynamic OpenAPI spec at `/v1/guardian/openapi.json` tells the AI everything — device names, online status, available container types — right in the tool descriptions. The `CLAUDE.md` / `GEMINI.md` gives usage tips. The AI can immediately start working:

```
You> how are my devices?

Claude> [calls list_devices]
  You have 3 devices. Living room and garage are online, office is offline.

You> what can the sensors container do?

Claude> [calls get_container_api("sensors")]
  It exposes: temperature (current reading), humidity (current reading),
  history (readings over time with configurable range).

You> show me temperature on all sensor devices

Claude> [calls call_devices(["container:sensors"], "/sensors/temperature", "GET")]
  Garage (dp-8b2a): 22.3°C

You> restart mosquitto everywhere

Claude> That would restart mosquitto on living room and garage. Proceed?

You> yes

Claude> [calls call_devices(["container:mosquitto"], "/system/containers/mosquitto/restart", "POST")]
  Living room: restarted, 12 clients reconnected
  Garage: restarted, 4 clients reconnected
```

### File Layout (Guardian additions)

```
devicepass-cli/
├── lib/
│   └── guardian/
│       ├── common.sh              # cast wrappers, account helpers
│       ├── claim.sh               # guardian claim
│       ├── list.sh                # guardian list
│       ├── status.sh              # guardian status
│       ├── fund.sh                # guardian fund
│       ├── balance.sh             # guardian balance
│       ├── transfer.sh            # guardian transfer
│       ├── revoke.sh              # guardian revoke
│       └── talk.sh                # guardian talk (50 lines)
```

---

## Part 4: Smart Contract

DevicePassRegistry — deployed separately (Foundry project).

```solidity
function claimDevice(address device, uint256 nonce, bytes calldata deviceSignature) external payable;
function transferDevice(address device, address newGuardian) external;
function revokeDevice(address device) external;
function passports(address device) external view returns (address device, address guardian, uint256 createdAt, bool active);

event PassportCreated(address indexed device, address indexed guardian);
event PassportTransferred(address indexed device, address indexed oldGuardian, address indexed newGuardian);
event PassportRevoked(address indexed device, address indexed guardian);
```

The hub and guardian CLI both read from this contract to verify ownership.

---

## Implementation Order

### Phase 1 — Device identity (offline, no chain)
1. ~~keccak256sum.c~~ ✓ done
2. ethsign.c — build, test
3. lib/display.sh, lib/config.sh
4. lib/identity.sh + init
5. lib/signing.sh + onboard
6. export-key, status (local)

### Phase 2 — Smart contract
7. DevicePassRegistry.sol — implement, test with Forge
8. Deploy to Anvil (local testnet)

### Phase 3 — Guardian management
9. guardian common.sh (cast wrappers)
10. guardian claim, status, list, fund, balance

### Phase 4 — Device serve (C) + Hub MVP (Go)
11. Hub (Go): device WebSocket endpoint (connect, auth, heartbeat)
12. Hub (Go): guardian auth endpoint (challenge-response, JWT)
13. serve.c: hub connection, auth, spec collection, spec push, metadata push
14. Hub: spec aggregation, fleet state, version-aware dedup
15. Hub: HTTP-over-WebSocket tunnel (request routing, correlation)
16. Hub: guardian fleet API (devices, containers, call, group/call, meta)
17. Hub: dynamic OpenAPI spec generation (/openapi.json)
18. serve.c: incoming tunnel request handler (HTTP proxy to containers)
19. serve.c: metadata endpoint handler (name/label updates from guardian)

### Phase 5 — AI integration
20. guardian talk — auth, scaffold workspace, launch AI CLI
21. End-to-end test: devicepass-cli serve → hub → guardian talk → AI controls device

### Phase 6 — Production
22. guardian transfer, revoke
23. Real chain deployment (Base testnet → mainnet)
24. Hub persistence, scaling, monitoring
25. Rate limiting per guardian

---

## Decisions Made

1. **Hub language:** Go. Strong WebSocket/concurrency support.
2. **Device serve language:** C. Minimal footprint, links against libcrypto (already present). Consistent with keccak256sum and ethsign.
3. **Tunnel protocol:** HTTP-over-WebSocket with JSON envelopes. Correlation ID for concurrent multiplexing. 1MB message limit for MVP, base64 encoding for binary payloads later.
4. **Spec versioning:** Version-aware dedup keyed by container type + `info.version`. MVP tracks versions; later: expose version drift to AI.
5. **Device naming:** Guardian sets name/labels via hub fleet API → routed through tunnel to device → device stores in `meta.json` → device pushes metadata to hub → hub includes in fleet state. Name lives on the device.
6. **pv-devicepass = devicepass-cli serve:** The `pv-devicepass` Pantavisor app calls `devicepass-cli serve` as its entrypoint. One C binary handles hub connection, tunnel, specs, and metadata.

## Open Questions

1. **Token refresh:** Guardian JWT lifetime? If `talk` sessions last hours, need refresh mechanism. Options: long-lived tokens (24h), or refresh endpoint the AI proxy can call transparently.

2. **Spec change during talk session:** If a device pushes new specs while a `talk` session is active, the AI's tools are stale. `mcp-openapi-proxy` re-fetches the spec periodically? Or accept staleness until next `talk`?

3. **Rate limiting / abuse:** Hub fleet API needs rate limiting per guardian. Group calls especially — `call_devices(["all"], ...)` on a 1000-device fleet could be expensive.

4. **Go WebSocket library:** gorilla/websocket (mature, archived) vs nhooyr/websocket (modern, context-aware) vs coder/websocket (nhooyr fork, maintained). Need to evaluate.

5. **Large payloads:** HTTP-over-WebSocket with 1MB JSON limit works for MVP. For firmware uploads, log streaming, or large config pushes: chunked transfer, binary WebSocket frames, or separate HTTP upload endpoint via pre-signed URL?

6. **Container port mapping:** How does `serve` know which local port maps to which container? Pantavisor metadata? Config file? Convention (container name → well-known port)?

7. **C WebSocket library:** libwebsockets (full-featured, ~200KB) vs minimal hand-rolled WebSocket-over-TLS using libcrypto's BIO/SSL? libwebsockets adds a dependency but handles framing, ping/pong, reconnect. Hand-rolled is smaller but more work.
