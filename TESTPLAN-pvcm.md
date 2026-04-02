# PVCM Protocol Test Plan

End-to-end testing of the PVCM protocol between pvcm-run (Linux)
and Zephyr native_sim_64 over PTY.

## Prerequisites

Build the native_sim_64 Zephyr target:

```bash
kas build kas/scarthgap.yaml:kas/bsp-base.yaml:kas/pv-mcu-zephyr.yaml:kas/mcu-machines/native-sim.yaml \
    --target mc:pv-mcu-zephyr:pvcm-zephyr-shell
```

Build pvcm-run for the host:

```bash
PV=build/workspace/sources/pantavisor
gcc -o /tmp/pvcm-run-test \
    $PV/pvcm-run/main.c \
    $PV/pvcm-run/pvcm_config.c \
    $PV/pvcm-run/pvcm_transport_uart.c \
    $PV/pvcm-run/pvcm_protocol.c \
    $PV/pvcm-run/pvcm_bridge.c \
    $PV/pvcm-run/pvcm_dbus_bridge.c \
    -I$PV -lpthread $(pkg-config --cflags --libs dbus-1)
```

The Zephyr executable is at:
```
build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/work/x86_64-yocto-linux/pvcm-zephyr-shell/3.6.0+git/build/zephyr/zephyr.exe
```

## Test 1: HELLO Handshake + Heartbeat

### Start Zephyr

```bash
EXE=build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/work/x86_64-yocto-linux/pvcm-zephyr-shell/3.6.0+git/build/zephyr/zephyr.exe
/lib64/ld-linux-x86-64.so.2 $EXE
```

Expected: two PTYs created (`uart` for shell, `uart_1` for PVCM).

### Connect pvcm-run

Use the `uart_1` PTY path:

```bash
echo '{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/Y","transport":"uart","baudrate":921600}}' > /tmp/r.json
/tmp/pvcm-run-test --name test --config /tmp/r.json
```

### Pass Criteria

- [x] HELLO handshake succeeds (`MCU connected: protocol=v1`)
- [x] Heartbeats arrive every ~5 seconds
- [x] Health status is OK, crash count is 0

## Test 2: HTTP Client (MCU calls Linux)

The Zephyr demo app runs HTTP tests automatically after connecting.
Start a test HTTP server before connecting:

```bash
python3 build/workspace/sources/pantavisor/pvcm-run/test/test_http_server.py &
```

### Pass Criteria

- [x] GET /api/status → 200 `{"status": "ok", "uptime": 42}`
- [x] GET /api/config → 200 `{"interval": 5, "mode": "auto"}`
- [x] POST /api/data with JSON body → 201 with echoed body
- [x] PUT /api/config → 200 with updated data
- [x] DELETE /api/data/1 → 200
- [x] PUT /api/upload 2KB binary → 200 (slow server, 3s delay)
- [x] Heartbeats continue during slow upload
- [x] GET works after slow upload completes

## Test 3: HTTP Server (Linux calls MCU)

The Zephyr demo registers a handler for `/sensor`. pvcm-run
listens on port 18081 for inbound HTTP requests.

### Call MCU from host

```bash
curl http://127.0.0.1:18081/sensor/temperature
```

### Expected

```json
{"temperature":22.4,"humidity":65}
```

### Pass Criteria

- [x] curl receives JSON response from MCU handler
- [x] Zephyr logs show INVOKE received and handler called
- [x] Proxy logs show REPLY frames received

## Test 4: Shell Access

While pvcm-run is connected to uart_1, the Zephyr shell is
accessible on uart (uart0).

```bash
screen /dev/pts/X   # uart0 PTY
```

### Pass Criteria

- [x] Shell prompt appears
- [x] `pv status` shows protocol version
- [x] Shell does not interfere with PVCM protocol on uart_1

## Architecture

```
Terminal 1 (Zephyr native_sim_64)     Terminal 2 (pvcm-run)        Terminal 3
─────────────────────────────         ──────────────────────         ──────────
zephyr.exe                            pvcm-run-test
  uart0 → shell                        reads/writes uart_1 PTY
  uart1 → PVCM protocol                  ↕ PVCM frames
    server: HELLO_RESP                  HTTP bridge:
    heartbeat: every 5s          ←       heartbeat tracking
    HTTP client: pvcm_get()      →       forwards to localhost:18080
    HTTP server: /sensor handler ←       listens on :18081           curl :18081
```

## UART Configuration (native_sim_64)

Board overlay `boards/native_sim_64.conf`:

```kconfig
CONFIG_UART_NATIVE_POSIX_PORT_1_ENABLE=y   # enable uart_1
CONFIG_PANTAVISOR_UART_DEVICE="uart_1"     # PVCM on uart_1
CONFIG_PANTAVISOR_BRIDGE=y                 # HTTP client/server
CONFIG_NATIVE_SIM_SLOWDOWN_TO_REAL_TIME=y  # wall-clock sync
```

---

# D-Bus Gateway Tests (native_sim_64)

## Prerequisites

Start a test D-Bus service on the session bus:

```bash
python3 build/workspace/sources/pantavisor/pvcm-run/test/test_dbus_service.py &
```

Connect pvcm-run with `--dbus-session`:

```bash
echo '{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/Y","transport":"uart","baudrate":921600}}' > /tmp/r.json
/tmp/pvcm-run-test --name test --config /tmp/r.json --dbus-session
```

## Test D1: D-Bus ListNames

```bash
# From Zephyr shell (uart0 PTY):
pv dbus list
```

### Pass Criteria

- [ ] Returns JSON array of bus names
- [ ] Contains `"org.freedesktop.DBus"`
- [ ] Contains `"org.pantavisor.TestService"` (if test service running)
- [ ] No timeout or error

## Test D2: D-Bus Method Call

```bash
pv dbus call org.pantavisor.TestService /test org.pantavisor.TestService Echo '["hello from MCU"]'
```

### Pass Criteria

- [ ] Returns `"hello from MCU"`
- [ ] No D-Bus error

## Test D3: D-Bus Method with Args

```bash
pv dbus call org.pantavisor.TestService /test org.pantavisor.TestService Add '[3,4]'
```

### Pass Criteria

- [ ] Returns `7`
- [ ] Correct JSON integer response

## Test D4: D-Bus Signal Subscription

```bash
pv dbus subscribe org.pantavisor.TestService /test org.pantavisor.TestService Tick
```

### Pass Criteria

- [ ] Returns `subscribed: sub_id=N`
- [ ] Shell prints `[signal] ... Tick: N` every second
- [ ] Heartbeats continue during signal delivery

## Test D5: D-Bus Unsubscribe

```bash
pv dbus unsubscribe 1
```

### Pass Criteria

- [ ] Returns `unsubscribed: sub_id=1`
- [ ] No more Tick signals appear

## Test D6: D-Bus Error Handling

```bash
pv dbus call org.nonexistent.Service /foo org.foo Bar
```

### Pass Criteria

- [ ] Returns D-Bus error (PVCM_DBUS_ERR_NO_SERVICE)
- [ ] Error message includes D-Bus error name
- [ ] No crash or timeout

---

# Hardware Tests (i.MX8MN RPMsg)

End-to-end testing on Variscite VAR-SOM-MX8M-NANO with Cortex-M7
over RPMsg/remoteproc. Two RPMsg channels: shell (ttyRPMSG0) and
PVCM protocol (ttyRPMSG1).

## Hardware Prerequisites

```bash
# Start M7 firmware
echo /storage > /sys/module/firmware_class/parameters/path
cp /storage/trails/current/pvcm-zephyr-shell/pvcm-zephyr-shell.elf /storage/
echo pvcm-zephyr-shell.elf > /sys/class/remoteproc/remoteproc0/firmware
echo start > /sys/class/remoteproc/remoteproc0/state
sleep 5

# Start pvcm-run
pvcm-run --name pvcm-zephyr-shell \
    --config /storage/trails/current/pvcm-zephyr-shell/run.json \
    --device /dev/ttyRPMSG1 &
```

### Stop / Restart (no reboot needed)

```bash
echo stop > /sys/class/remoteproc/remoteproc0/state
sleep 3  # must reach "offline" before changing firmware
echo start > /sys/class/remoteproc/remoteproc0/state
```

## Test H1: RPMsg Channel Creation

```bash
echo start > /sys/class/remoteproc/remoteproc0/state
sleep 5
ls -la /dev/ttyRPMSG*
dmesg | grep "creating channel"
```

### Pass Criteria

- [ ] `/dev/ttyRPMSG0` exists (char device, shell channel)
- [ ] `/dev/ttyRPMSG1` exists (char device, protocol channel)
- [ ] dmesg: `creating channel rpmsg-tty addr 0x400` and `addr 0x401`

## Test H2: HELLO Handshake + Heartbeat

```bash
pvcm-run --name pvcm-zephyr-shell \
    --config /storage/trails/current/pvcm-zephyr-shell/run.json \
    --device /dev/ttyRPMSG1
```

### Pass Criteria

- [ ] `MCU connected: protocol=v1 fw=v1 baudrate=921600`
- [ ] Heartbeats every ~5s: `heartbeat: status=OK uptime=Ns crashes=0`
- [ ] No CRC or sync mismatches after handshake

## Test H3: Shell over RPMsg

```bash
cat /dev/ttyRPMSG0 &
printf "\r" > /dev/ttyRPMSG0; sleep 3
printf "pv status\r" > /dev/ttyRPMSG0; sleep 2
printf "pv heartbeat\r" > /dev/ttyRPMSG0; sleep 2
printf "help\r" > /dev/ttyRPMSG0; sleep 2
```

### Pass Criteria

- [ ] `mcu:~$` prompt appears after initial CR
- [ ] `pv status`: `PVCM protocol v1`, `Transport: RPMsg`, `Heartbeat: 5000 ms`
- [ ] `pv heartbeat`: shows uptime in seconds
- [ ] `help`: lists `pv`, `kernel`, `devmem` commands
- [ ] Shell does not interfere with protocol channel

## Test H4: HTTP Linux → MCU

```bash
printf "GET /sensor HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -w 10 127.0.0.1 18081
```

### Expected

```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 51
Connection: close

{"temperature":22.4,"humidity":65,"uptime_ms":NNNN}
```

### Pass Criteria

- [ ] HTTP 200 OK with JSON body
- [ ] `uptime_ms` reflects actual M7 uptime
- [ ] Response within 1 second

## Test H5: HTTP MCU → Linux

```bash
# Via shell (pvcm-run must be running):
cat /dev/ttyRPMSG0 &
printf "\r" > /dev/ttyRPMSG0; sleep 2
printf "pv http /cgi-bin/logs\r" > /dev/ttyRPMSG0; sleep 12
```

### Pass Criteria

- [ ] Shell shows `GET /cgi-bin/logs ...`
- [ ] Shell shows `HTTP NNN (N bytes)` with response body
- [ ] Bridge log: `HTTP_REQ: GET /cgi-bin/logs` and `upstream response: NNN`

## Test H6: Stop / Start

```bash
echo stop > /sys/class/remoteproc/remoteproc0/state; sleep 3
cat /sys/class/remoteproc/remoteproc0/state   # "offline"
echo start > /sys/class/remoteproc/remoteproc0/state; sleep 5
ls /dev/ttyRPMSG*
# Reconnect pvcm-run and verify handshake + shell
```

### Pass Criteria

- [ ] State reaches `offline` after stop
- [ ] Both ttyRPMSG devices reappear after start
- [ ] Handshake succeeds on reconnect
- [ ] Shell works after restart
- [ ] No stale data from previous session

## Test H7: Sequential Load (20 requests)

```bash
SUCCESS=0; FAIL=0; i=0
while [ $i -lt 20 ]; do
  RESP=$(printf "GET /sensor HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -w 5 127.0.0.1 18081)
  if echo "$RESP" | grep -q "200 OK"; then SUCCESS=$((SUCCESS+1))
  else FAIL=$((FAIL+1)); fi
  i=$((i+1))
done
echo "$SUCCESS OK, $FAIL FAIL out of 20"
```

### Pass Criteria

- [ ] 20/20 return HTTP 200 OK
- [ ] Each response has valid JSON with incrementing `uptime_ms`
- [ ] Stream IDs increment (no reuse)
- [ ] Heartbeats continue (no gaps > 10s)

## Test H8: Parallel Load (5 concurrent)

```bash
i=0
while [ $i -lt 5 ]; do
  (printf "GET /sensor HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -w 10 127.0.0.1 18081 | head -1) &
  i=$((i+1))
done
wait
```

### Pass Criteria

- [ ] All 5 return HTTP 200 OK
- [ ] No crashes or protocol corruption
- [ ] Heartbeats resume after burst

## Test H9: Sustained Load (60 seconds)

```bash
END=$(($(date +%s) + 60)); COUNT=0; FAIL=0
while [ $(date +%s) -lt $END ]; do
  RESP=$(printf "GET /sensor HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -w 5 127.0.0.1 18081)
  if echo "$RESP" | grep -q "200 OK"; then COUNT=$((COUNT+1))
  else FAIL=$((FAIL+1)); fi
done
echo "60s: $COUNT OK, $FAIL FAIL"
```

### Pass Criteria

- [ ] Zero failures over 60 seconds
- [ ] Throughput > 1 req/s
- [ ] Heartbeats never stop
- [ ] M7 uptime increases monotonically

## Test H10: D-Bus ListNames (Hardware)

Requires pvcm-run started with `--dbus-socket` and `--route`:

```bash
pvcm-run --name pvcm-zephyr-shell \
    --device /dev/ttyRPMSG1 --transport rpmsg \
    --dbus-socket /volumes/os/docker--pvrun-dbus/system_bus_socket \
    --route pv-ctrl=unix:/pv/pv-ctrl \
    --route pvr-sdk=tcp:127.0.0.1:12368 &
```

```bash
# From Zephyr shell (ttyRPMSG0):
pv dbus list
```

### Pass Criteria

- [x] Returns JSON array of system bus names
- [x] Contains `"net.connman"`, `"org.pantacor.PvWificonnect"`, `"org.freedesktop.NetworkManager"`
- [x] Response within 1 second
- [x] Heartbeats continue during D-Bus calls

## Test H11: D-Bus Method Call (Hardware)

```bash
# Bare args work (Zephyr shell strips JSON quotes):
pv dbus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner [net.connman]
```

### Pass Criteria

- [x] Returns unique bus name (e.g. `":1.0"`)
- [x] No errors
- [x] Heartbeats continue

## Test H12: D-Bus Signal Subscription (Hardware)

```bash
pv dbus subscribe org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameOwnerChanged
```

### Pass Criteria

- [x] Subscription confirmed (`subscribed: sub_id=1`)
- [x] Signals appear when services start/stop
- [x] No interference with heartbeat or HTTP

## Test H13: D-Bus Truncation Error (Hardware)

```bash
# GetTechnologies returns a(oa{sv}) — exceeds 246 byte frame limit:
pv dbus call net.connman / net.connman.Manager GetTechnologies
```

### Pass Criteria

- [x] Returns `D-Bus error 6: reply exceeds 245 byte frame limit`
- [x] Error code is PVCM_DBUS_ERR_TRUNCATED (6)
- [x] No crash or hang

## Test H14: Transport Ping — Multi-frame (Hardware)

Tests bidirectional RPMsg transport with multi-frame responses.
Proxy splits the requested total size into 400-byte frames.

```bash
pv ping 100      # 1 frame
pv ping 500      # 2 frames
pv ping 1000     # 3 frames
pv ping 10000    # 25 frames
```

### Pass Criteria

- [x] `pv ping 100` — PASS: 1 frame, 100 bytes
- [x] `pv ping 500` — PASS: 2 frames, 500 bytes
- [x] `pv ping 1000` — PASS: 3 frames, 1000 bytes
- [x] `pv ping 10000` — PASS: 25 frames, 10000 bytes
- [x] Heartbeats continue throughout all tests
- [x] MCU stays alive after multi-frame delivery

## Test H15: HTTP via pv-ctrl Unix Socket (Hardware)

Requires pvcm-run with `--route`:

```bash
pvcm-run --name pvcm-zephyr-shell \
    --device /dev/ttyRPMSG1 --transport rpmsg \
    --dbus-socket /volumes/os/docker--pvrun-dbus/system_bus_socket \
    --route pv-ctrl=unix:/pv/pv-ctrl \
    --route pvr-sdk=tcp:127.0.0.1:12368 &
```

```bash
# Small response (error)
pv http http://pv-ctrl.pvlocal/x
# Large response (2337 bytes buildinfo)
pv http http://pv-ctrl.pvlocal/buildinfo
# Medium response (container list)
pv http http://pv-ctrl.pvlocal/containers
# TCP route (pvr-sdk)
pv http pvr-sdk /api/v1/device/info
```

### Pass Criteria

- [x] `/x` — HTTP 400 (32 bytes)
- [x] `/buildinfo` — HTTP 200 (2337 bytes, full body)
- [x] `/containers` — HTTP 200 (752 bytes)
- [x] TCP route — HTTP 404 (default pantavisor HTTP)
- [x] MCU stays alive after all requests
- [x] Heartbeats continue throughout

## Test H16: HTTP POST/PUT/DELETE (Hardware)

```bash
pv http POST http://pv-ctrl.pvlocal/user-meta {"test":"hello"}
pv http PUT http://pv-ctrl.pvlocal/user-meta {"updated":true}
pv http DELETE http://pv-ctrl.pvlocal/user-meta/test
```

### Pass Criteria

- [x] POST — body delivered (proxy shows `body=12 bytes`), response received
- [x] PUT — body delivered (proxy shows `body=14 bytes`), response received
- [x] DELETE — routed correctly, HTTP 404 response
- [x] Content-Type: application/json header sent automatically with body
- [x] MCU stays alive, heartbeats continue

## Test H17: Large Header Streaming (Hardware)

```bash
pv hdrtest 100     # 1 frame
pv hdrtest 600     # 2 frames
pv hdrtest 1500    # 4 frames
pv hdrtest 3000    # 7 frames
```

### Pass Criteria

- [x] 100-byte header — PASS, routed to pv-ctrl
- [x] 600-byte header — PASS, routed to pv-ctrl
- [x] 1500-byte header — PASS, routed to pv-ctrl
- [x] 3000-byte header — PASS, Host header preserved, routed correctly
- [x] MCU stays alive throughout

## Test H18: D-Bus Streaming (Hardware)

D-Bus calls and responses use streaming DBUS_DATA frames.
No fixed 246-byte limit on results.

```bash
pv dbus list
pv dbus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner [net.connman]
pv dbus subscribe org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameOwnerChanged
```

### Pass Criteria

- [x] ListNames — full JSON array via streaming DBUS_DATA
- [x] GetNameOwner — `:1.0` via streaming response
- [x] Subscribe — `sub_id=1`, signals delivered via streaming
- [x] All async — shell uses semaphore convenience, SDK is non-blocking
- [x] Heartbeats continue throughout

## Key Configuration

| Setting | Value | Why |
|---------|-------|-----|
| `CONFIG_IPM_IMX_MAX_DATA_SIZE_4` | `y` | MU register must match Linux DTB mbox index 1 |
| `CONFIG_OPENAMP_RSC_TABLE_NUM_RPMSG_BUFF` | `32` | Prevents TX vring exhaustion |
| `CONFIG_OPENAMP_MASTER` | `n` | M7 is remote/device role |
| `cfmakeraw()` on ttyRPMSG | required | Binary protocol, no line discipline |
| Residual buffer in proxy | required | Handles concatenated frames in tty read |
| `ipm_send(id=1)` | hardcoded | Matches Linux DTB mbox rx index 1 |
| `METAL_MAX_DEVICE_REGIONS` | `2` | Shared memory + resource table |
| `memset(SHM_START_ADDR)` | at M7 boot | Clears stale vrings for stop/start |

## Test H19: D-Bus Large Payload (Hardware)

Previously truncated at 246 bytes — now streaming via DBUS_DATA.

```bash
pv dbus call net.connman / net.connman.Manager GetTechnologies
pv dbus call net.connman / net.connman.Manager GetServices
```

### Pass Criteria

- [x] GetTechnologies — full `a(oa{sv})` result (~450 bytes JSON)
- [x] GetServices — full service config (~900 bytes with IPv4/IPv6/DNS)
- [x] Previously truncated results now delivered complete
- [x] MCU stays alive, heartbeats continue
