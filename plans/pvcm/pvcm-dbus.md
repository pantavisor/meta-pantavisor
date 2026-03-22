# PVCM DBus -- Technical Plan

## Overview

PVCM DBus is the DBus integration layer of Pantavisor MCU. It is a
supplement to the main `pvcm-plan.md` covering the DBus-specific aspects
of the service mesh gateway.

Once an MCU is a Pantavisor container and a peer in the xconnect service
mesh, it gains access to DBus system services -- NetworkManager, BlueZ,
ModemManager, PipeWire, systemd -- without any DBus implementation in the
firmware itself. This is the most trivial way to interface with DBus backend
services for MCUs that exists for RTOS firmware.

The layering of responsibility:

```
MCU firmware         knows what to call, not how to call it
RTOS SDK             handles DBus message assembly and type marshalling
pvcm-manager         handles transport, connection, xconnect routing
xconnect             handles socket injection, SASL identity, access control
DBus service         does the actual work (NetworkManager, BlueZ, etc.)
```

The MCU developer never touches Unix sockets, SASL authentication, DBus
wire format alignment rules, or connection lifecycle. Two tiers available:

- **Tier 1**: DBus message assembly in the RTOS SDK -- developer knows the
  DBus API, SDK handles everything below the message content level
- **Tier 2**: REST wrapper containers -- developer calls clean REST endpoints,
  no DBus knowledge required anywhere in the firmware

---

## How DBus Connections Reach the MCU

pvcm-manager acts as the DBus client on behalf of the MCU container. It reads
the xconnect-graph to discover which DBus links the MCU container has declared
as required in its `run.json`. xconnect injects the proxied DBus socket into
the pvcm-manager namespace (or a bridge namespace). pvcm-manager connects to
that socket -- SASL authentication is handled by xconnect at injection time
using role-based identity masquerading (see XCONNECT.md). pvcm-manager never
re-authenticates, it just sends and receives messages on the established
connection.

```
MCU (RTOS SDK)          pvcm-manager (Linux)          xconnect / DBus
──────────────          ────────────────────          ────────────────
pvcm_dbus_send()  -->   receive PVCM frame            DBus SASL handled
                        unmarshal args               once at connection
                        marshal to DBus wire    -->   write to injected
                        format                        socket

pvcm_dbus_cb()    <--   receive DBus reply      <--   read from socket
                        marshal to JSON
                        send PVCM frame

pvcm_dbus_signal()<--   DBus signal fires        <--  match rule triggered
                        marshal to JSON
                        push PVCM frame to MCU
```

### services.json and run.json for MCU DBus

The MCU container declares its DBus requirements in `run.json` exactly as
any Linux container would:

```json
{
  "services": {
    "required": [
      {
        "name": "system-bus",
        "type": "dbus",
        "interface": "org.freedesktop.NetworkManager",
        "target": "/run/dbus/system_bus_socket",
        "role": "any"
      },
      {
        "name": "bluez-bus",
        "type": "dbus",
        "interface": "org.bluez",
        "target": "/run/dbus/bluez_bus_socket",
        "role": "any"
      }
    ]
  }
}
```

pv-xconnect processes this and creates the links. pvcm-manager reads the
xconnect-graph, finds the MCU consumer links, and connects to the injected
sockets. The MCU firmware calls services by the declared `name` field.

### MCU as DBus Service Provider

The MCU container declares exported services in `services.json`:

```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    {
      "name": "mcu-sensor",
      "type": "dbus",
      "socket": "/run/pv/mcu/sensor.sock"
    }
  ]
}
```

pvcm-manager registers `com.pantavisor.mcu` on the Linux system bus and
forwards calls from Linux containers to the MCU via `PVCM_OP_DBUS_INVOKE`.

---

## Signal Subscriptions

pvcm-manager adds DBus match rules on behalf of the MCU when it receives
a `PVCM_OP_DBUS_SUBSCRIBE` message:

```c
void on_pvcm_dbus_subscribe(pvcm_dbus_sub_t *req) {
    dbus_route_t *route = pvcm_dbus_route_lookup(req->service);
    if (!route) { pvcm_nack(req->sub_id); return; }

    char match[256];
    snprintf(match, sizeof(match),
             "type='signal',interface='%s',member='%s'%s%s",
             req->interface, req->member,
             req->path[0] ? ",path='" : "",
             req->path[0] ? req->path  : "");

    dbus_bus_add_match(route->conn, match, NULL);
    pvcm_signal_handler_add(req->sub_id, req->interface,
                             req->member, route->conn);
    pvcm_ack(req->sub_id);
}

/* called by libevent when signal arrives */
DBusHandlerResult on_dbus_signal(DBusConnection *conn,
                                   DBusMessage *msg, void *ctx) {
    if (dbus_message_get_type(msg) != DBUS_MESSAGE_TYPE_SIGNAL)
        return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    pvcm_signal_handler_t *h = pvcm_signal_handler_find(
        dbus_message_get_interface(msg),
        dbus_message_get_member(msg)
    );
    if (!h) return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;

    pvcm_dbus_signal_t *sig = dbus_message_to_pvcm_signal(msg, h->sub_id);
    pvcm_transport_send(sig, pvcm_dbus_signal_size(sig));
    pvcm_dbus_signal_free(sig);
    return DBUS_HANDLER_RESULT_HANDLED;
}
```

---

## MCU Service Registration on Linux System Bus

When the MCU exposes a service via `pvcm_dbus_expose()`, pvcm-manager
registers the corresponding object path on the Linux system bus:

```c
void on_pvcm_dbus_expose(pvcm_dbus_expose_t *req) {
    /* register DBus object path on system bus */
    dbus_connection_register_object_path(
        system_bus_conn,
        req->path,           /* e.g. /com/pantavisor/mcu/sensor/temperature */
        &vtable,
        (void*)(uintptr_t)req->endpoint_id
    );
    pvcm_ack(req->endpoint_id);
}

/* called when a Linux container calls the MCU DBus method */
void on_linux_calls_mcu(DBusConnection *conn,
                          DBusMessage *msg,
                          void *endpoint_id_ptr) {
    uint8_t endpoint_id = (uint8_t)(uintptr_t)endpoint_id_ptr;

    /* translate DBus message to JSON args */
    char *args = dbus_message_to_json(msg);

    /* invoke on MCU */
    uint8_t invoke_id = next_invoke_id++;
    pending_invoke_add(invoke_id, conn, msg);

    pvcm_dbus_invoke_t invoke = {
        .op          = PVCM_OP_DBUS_INVOKE,
        .invoke_id   = invoke_id,
        .endpoint_id = endpoint_id,
    };
    strncpy(invoke.args, args, sizeof(invoke.args) - 1);
    pvcm_transport_send(&invoke, sizeof(invoke));
    free(args);
}

/* called when MCU sends PVCM_OP_DBUS_INVOKE_RESP */
void on_mcu_invoke_resp(pvcm_dbus_invoke_resp_t *resp) {
    pending_invoke_t *p = pending_invoke_find(resp->invoke_id);
    if (!p) return;

    /* translate JSON response back to DBus reply */
    DBusMessage *reply = json_to_dbus_reply(p->msg, resp->result);
    dbus_connection_send(p->conn, reply, NULL);
    dbus_message_unref(reply);
    pending_invoke_remove(resp->invoke_id);
}
```

---

## Tier 1 -- DBus Message Assembly in RTOS SDK

### Design Principle

The SDK handles everything below message content level:
- Unix socket management
- SASL authentication
- TCP/IP if remote
- Message framing and serial number tracking
- Timeout and reply correlation
- Signal match rule management

The developer handles:
- DBus destination, object path, interface, method names
- Argument types and order for methods they call
- Reply parsing

This is still knowledge the developer needs -- but it is the same knowledge
they would need to use any DBus service from any language. The transport
complexity is completely removed.

### SDK API

```c
/* pvcm_dbus.h */

/* --- message construction --- */

pvcm_dbus_msg_t *pvcm_dbus_call_new(
    const char *destination,   /* "org.freedesktop.NetworkManager" */
    const char *path,          /* "/org/freedesktop/NetworkManager" */
    const char *interface,     /* "org.freedesktop.NetworkManager" */
    const char *method         /* "GetAllDevices" */
);

/* typed argument appenders */
void pvcm_dbus_append_string (pvcm_dbus_msg_t *msg, const char *val);
void pvcm_dbus_append_uint32 (pvcm_dbus_msg_t *msg, uint32_t val);
void pvcm_dbus_append_int32  (pvcm_dbus_msg_t *msg, int32_t val);
void pvcm_dbus_append_bool   (pvcm_dbus_msg_t *msg, bool val);
void pvcm_dbus_append_byte   (pvcm_dbus_msg_t *msg, uint8_t val);
void pvcm_dbus_append_path   (pvcm_dbus_msg_t *msg, const char *path);

/* container open/close */
void pvcm_dbus_open_array    (pvcm_dbus_msg_t *msg, const char *elem_sig);
void pvcm_dbus_close_array   (pvcm_dbus_msg_t *msg);
void pvcm_dbus_open_dict     (pvcm_dbus_msg_t *msg);
void pvcm_dbus_close_dict    (pvcm_dbus_msg_t *msg);
void pvcm_dbus_open_struct   (pvcm_dbus_msg_t *msg);
void pvcm_dbus_close_struct  (pvcm_dbus_msg_t *msg);
void pvcm_dbus_open_variant  (pvcm_dbus_msg_t *msg, const char *sig);
void pvcm_dbus_close_variant (pvcm_dbus_msg_t *msg);

/* --- sending --- */

typedef void (*pvcm_dbus_reply_cb_t)(pvcm_dbus_msg_t *reply,
                                      int error, void *ctx);

int  pvcm_dbus_send    (pvcm_dbus_msg_t *msg,
                        pvcm_dbus_reply_cb_t cb, void *ctx);
void pvcm_dbus_msg_free(pvcm_dbus_msg_t *msg);

/* --- reply parsing -- iterator based --- */

pvcm_dbus_iter_t  pvcm_dbus_iter        (pvcm_dbus_msg_t *msg);
bool              pvcm_dbus_iter_next   (pvcm_dbus_iter_t *it);
char              pvcm_dbus_iter_type   (pvcm_dbus_iter_t *it);
const char       *pvcm_dbus_iter_string (pvcm_dbus_iter_t *it);
uint32_t          pvcm_dbus_iter_uint32 (pvcm_dbus_iter_t *it);
int32_t           pvcm_dbus_iter_int32  (pvcm_dbus_iter_t *it);
bool              pvcm_dbus_iter_bool   (pvcm_dbus_iter_t *it);
uint8_t           pvcm_dbus_iter_byte   (pvcm_dbus_iter_t *it);
pvcm_dbus_iter_t  pvcm_dbus_iter_recurse(pvcm_dbus_iter_t *it);

/* --- signal subscription --- */

typedef void (*pvcm_dbus_signal_cb_t)(pvcm_dbus_msg_t *signal, void *ctx);

int pvcm_dbus_subscribe(
    const char           *service,    /* "org.freedesktop.NetworkManager" */
    const char           *path,       /* NULL = any */
    const char           *interface,  /* "org.freedesktop.NetworkManager" */
    const char           *member,     /* "StateChanged" */
    pvcm_dbus_signal_cb_t cb,
    void                 *ctx
);
int pvcm_dbus_unsubscribe(int sub_id);

/* --- MCU service exposure --- */

typedef void (*pvcm_dbus_handler_t)(pvcm_dbus_msg_t *call,
                                     pvcm_dbus_msg_t *reply,
                                     void *ctx);

int pvcm_dbus_expose(
    const char          *path,
    const char          *interface,
    const char          *method,
    pvcm_dbus_handler_t  handler,
    void                *ctx
);
```

### Usage Example -- NetworkManager WiFi Connect

```c
void on_wifi_reply(pvcm_dbus_msg_t *reply, int error, void *ctx) {
    if (error) { ui_show_error("WiFi connect failed"); return; }

    pvcm_dbus_iter_t it = pvcm_dbus_iter(reply);
    pvcm_dbus_iter_next(&it);
    const char *active_conn = pvcm_dbus_iter_string(&it);
    ui_show_wifi_connected(active_conn);
}

void connect_wifi(const char *ssid, const char *psk) {
    pvcm_dbus_msg_t *msg = pvcm_dbus_call_new(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        "AddAndActivateConnection"
    );

    pvcm_dbus_open_array(msg, "{sa{sv}}");
      pvcm_dbus_open_dict(msg);
        pvcm_dbus_append_string(msg, "802-11-wireless");
        pvcm_dbus_open_array(msg, "{sv}");
          pvcm_dbus_open_dict(msg);
            pvcm_dbus_append_string(msg, "ssid");
            pvcm_dbus_open_variant(msg, "ay");
              pvcm_dbus_open_array(msg, "y");
              for (int i = 0; ssid[i]; i++)
                  pvcm_dbus_append_byte(msg, (uint8_t)ssid[i]);
              pvcm_dbus_close_array(msg);
            pvcm_dbus_close_variant(msg);
          pvcm_dbus_close_dict(msg);
          /* append 802-11-wireless-security with psk similarly */
        pvcm_dbus_close_array(msg);
      pvcm_dbus_close_dict(msg);
    pvcm_dbus_close_array(msg);
    pvcm_dbus_append_path(msg, "/");
    pvcm_dbus_append_path(msg, "/");

    pvcm_dbus_send(msg, on_wifi_reply, NULL);
    pvcm_dbus_msg_free(msg);
}
```

### Usage Example -- NetworkManager State Signal

```c
void on_nm_state(pvcm_dbus_msg_t *signal, void *ctx) {
    pvcm_dbus_iter_t it = pvcm_dbus_iter(signal);
    pvcm_dbus_iter_next(&it);
    uint32_t state = pvcm_dbus_iter_uint32(&it);
    /* NM_STATE_CONNECTED_GLOBAL = 70 */
    if (state == 70) ui_show_online();
    else             ui_show_offline();
}

void subscribe_network_state(void) {
    pvcm_dbus_subscribe(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        "StateChanged",
        on_nm_state, NULL
    );
}
```

### Usage Example -- MCU Exposes Sensor to Linux

```c
void on_get_temperature(pvcm_dbus_msg_t *call,
                         pvcm_dbus_msg_t *reply, void *ctx) {
    float temp = sensor_read_temperature();
    pvcm_dbus_append_string(reply, "celsius");
    pvcm_dbus_append_uint32(reply, (uint32_t)(temp * 100));
}

void expose_sensor(void) {
    pvcm_dbus_expose(
        "/com/pantavisor/mcu/sensor/temperature",
        "com.pantavisor.mcu.Sensor",
        "GetTemperature",
        on_get_temperature, NULL
    );
}
```

From any Linux container:

```python
import dbus
bus = dbus.SystemBus()
mcu = dbus.Interface(
    bus.get_object("com.pantavisor.mcu",
                   "/com/pantavisor/mcu/sensor/temperature"),
    "com.pantavisor.mcu.Sensor"
)
unit, value = mcu.GetTemperature()
print(f"{value / 100.0} {unit}")
```

### PVCM DBus Wire Format

DBus messages are serialised to a compact binary format for PVCM transport.
Removes the 8-byte alignment padding from standard DBus wire format:

```
PVCM DBus frame body: sequence of typed values
[ type_tag 1B | value ]

type_tag:
  0x01  string    [ len 2B | utf8 bytes ]
  0x02  uint32    [ 4B LE ]
  0x03  int32     [ 4B LE ]
  0x04  bool      [ 1B ]
  0x05  byte      [ 1B ]
  0x06  path      [ len 2B | utf8 bytes ]
  0x07  array     [ count 2B | elements ]
  0x08  dict_pair [ key | value ]
  0x09  struct    [ count 1B | elements ]
  0x0A  variant   [ sig_len 1B | sig | value ]
  0x0B  end       closes array/dict/struct/variant
```

pvcm-manager translates between this compact format and standard DBus wire
format when bridging to the injected sockets.

### Memory Budget on MCU

```
pvcm_dbus.c (message assembly + parsing)    ~4KB flash
pvcm_dbus_transport.c (framing, shared)     ~2KB flash
message buffer (stack allocated)            512B RAM per in-flight call
signal callback table (8 entries)           ~200B RAM
expose handler table (4 entries)            ~100B RAM

Total SDK addition for DBus Tier 1:         ~6KB flash, ~1KB RAM
```

Fits on STM32G0, RP2040, nRF52, and all i.MX M core targets.

---

## Tier 2 -- REST Wrapper Containers

For developers who do not want to deal with DBus API shapes, a catalog of
companion containers wraps common Linux system services as clean REST APIs.

### Container Catalog

**pv-network-bridge** (NetworkManager)
```
GET  /network/status            connection state, IP address
GET  /network/scan              visible WiFi access points
POST /network/connect           { "ssid": "x", "psk": "y" }
POST /network/disconnect
GET  /network/devices           network interfaces list
```

**pv-bluetooth-bridge** (BlueZ)
```
GET  /bluetooth/scan            discovered devices
POST /bluetooth/scan/start
POST /bluetooth/scan/stop
POST /bluetooth/pair            { "address": "AA:BB:CC:DD:EE:FF" }
POST /bluetooth/connect         { "address": "..." }
POST /bluetooth/disconnect      { "address": "..." }
GET  /bluetooth/devices         paired devices
```

**pv-modem-bridge** (ModemManager)
```
GET  /modem/status              signal strength, registration
GET  /modem/location            GPS fix
POST /modem/sms/send            { "to": "+49...", "text": "..." }
GET  /modem/sms/inbox
```

**pv-audio-bridge** (PipeWire / PulseAudio)
```
GET  /audio/volume
POST /audio/volume              { "level": 75 }
GET  /audio/sources
GET  /audio/sinks
POST /audio/default-sink        { "name": "..." }
```

### How Wrapper Containers Integrate

Each wrapper container declares its REST service in `services.json` and
consumes the DBus service it wraps via `run.json`. The MCU container
declares it needs the REST endpoint in its own `run.json`. pv-xconnect
wires it together:

```
pv-network-bridge/services.json:
  exports: "network" (type: rest, socket: /run/pv-network-bridge/api.sock)

pv-network-bridge/run.json:
  requires: "system-bus" (type: dbus, interface: org.freedesktop.NetworkManager)

mcu-frontend/run.json:
  requires: "network" (type: rest, target: /run/pv/services/network.sock)
```

pv-xconnect injects the REST socket into both pv-network-bridge (for the
DBus connection) and pvcm-manager (for the MCU REST bridge). The MCU calls
`pvcm_post("/network/connect", ...)` and the request flows through
pvcm-manager -> REST socket -> pv-network-bridge -> DBus -> NetworkManager.

### Custom Wrapper Containers

Any team can write a wrapper for their own internal services. The pattern:

1. Write a small HTTP server (Go preferred -- single binary, fast startup)
2. Declare it in `services.json`
3. MCU container declares it in `run.json`
4. Call it via `pvcm_post()` / `pvcm_get()`

A custom wrapper is typically an afternoon of work. It updates independently
of the MCU firmware via standard Pantavisor OTA.

```go
// pv-network-bridge excerpt -- wraps NetworkManager DBus as REST
func handleConnect(w http.ResponseWriter, r *http.Request) {
    var req struct {
        SSID string `json:"ssid"`
        PSK  string `json:"psk"`
    }
    json.NewDecoder(r.Body).Decode(&req)

    conn, err := nm.AddAndActivateConnection(req.SSID, req.PSK)
    if err != nil {
        http.Error(w, err.Error(), 500)
        return
    }
    json.NewEncoder(w).Encode(map[string]string{"connection": conn})
}
```

---

## Developer Decision Tree

```
Do you know the DBus API you want to call?

  YES, comfortable with DBus types
  --> Tier 1: pvcm_dbus_call_new() + typed appenders
      direct DBus method calls from firmware
      signal subscriptions as callbacks
      no extra container needed

  YES but want something simpler
  --> Tier 2 with custom wrapper container
      write a small REST wrapper once
      MCU calls clean REST endpoints forever
      wrapper updates independently of firmware

  NO / just want it to work
  --> Tier 2 with catalog container
      drop pv-network-bridge / pv-bluetooth-bridge into revision
      MCU calls /network/connect, /bluetooth/pair
      no DBus knowledge required anywhere
```

---

## pvcm-manager DBus Bridge -- Startup

```c
void pvcm_dbus_bridge_init(pvcm_transport_t *transport) {
    xconnect_graph_t *graph = pvcm_fetch_xconnect_graph();

    for each link in graph where consumer == MCU_CONTAINER_NAME:
        if link.type == "dbus":
            /* connect to the injected socket */
            /* SASL auth already handled by xconnect */
            DBusConnection *conn = dbus_connect_to_socket(link.target);
            pvcm_dbus_route_add(link.name, link.interface, conn, link.role);

        if link.type == "rest":
            pvcm_rest_route_add(link.name, link.socket);

    for each link in graph where provider == MCU_CONTAINER_NAME:
        if link.type == "dbus":
            /* register MCU service on system bus */
            dbus_bus_request_name(system_bus, "com.pantavisor.mcu", 0, NULL);
            pvcm_dbus_provider_register(link.name, link.interface);

    /* watch for xconnect-graph changes as containers restart */
    pvcm_watch_xconnect_graph(pvcm_dbus_bridge_reconcile);
}
```

### Message Dispatch

```c
void on_pvcm_dbus_call(pvcm_dbus_call_t *req) {
    dbus_route_t *route = pvcm_dbus_route_lookup(req->path);
    if (!route) { pvcm_dbus_nack(req->req_id); return; }

    /* deserialise PVCM compact format to DBus wire format */
    DBusMessage *msg = pvcm_to_dbus_message(req);

    dbus_pending_call_t *pending;
    dbus_connection_send_with_reply(route->conn, msg, &pending, 5000);
    dbus_pending_call_set_notify(pending, on_dbus_reply,
                                  (void*)(uintptr_t)req->req_id, NULL);
    dbus_message_unref(msg);
}

void on_dbus_reply(DBusPendingCall *pending, void *user_data) {
    uint8_t req_id = (uint8_t)(uintptr_t)user_data;
    DBusMessage *reply = dbus_pending_call_steal_reply(pending);

    pvcm_dbus_resp_t *resp = dbus_message_to_pvcm(reply, req_id);
    pvcm_transport_send(resp, pvcm_dbus_resp_size(resp));

    dbus_message_unref(reply);
    pvcm_dbus_resp_free(resp);
}
```
