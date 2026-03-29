# PVCM Protocol Test Plan

End-to-end testing of the PVCM protocol between pvcm-proxy (Linux)
and Zephyr native_sim_64 over PTY.

## Prerequisites

Build the native_sim_64 Zephyr target:

```bash
kas build kas/scarthgap.yaml:kas/bsp-base.yaml:kas/pv-mcu-zephyr.yaml:kas/mcu-machines/native-sim.yaml \
    --target mc:pv-mcu-zephyr:pvcm-zephyr-shell
```

Build pvcm-proxy for the host:

```bash
PV=build/workspace/sources/pantavisor
gcc -o /tmp/pvcm-proxy-test \
    $PV/pvcm-proxy/main.c \
    $PV/pvcm-proxy/pvcm_config.c \
    $PV/pvcm-proxy/pvcm_transport_uart.c \
    $PV/pvcm-proxy/pvcm_protocol.c \
    $PV/pvcm-proxy/pvcm_bridge.c \
    -I$PV -lpthread
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

### Connect pvcm-proxy

Use the `uart_1` PTY path:

```bash
echo '{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/Y","transport":"uart","baudrate":921600}}' > /tmp/r.json
/tmp/pvcm-proxy-test --name test --config /tmp/r.json
```

### Pass Criteria

- [x] HELLO handshake succeeds (`MCU connected: protocol=v1`)
- [x] Heartbeats arrive every ~5 seconds
- [x] Health status is OK, crash count is 0

## Test 2: HTTP Client (MCU calls Linux)

The Zephyr demo app runs HTTP tests automatically after connecting.
Start a test HTTP server before connecting:

```bash
python3 build/workspace/sources/pantavisor/pvcm-proxy/test/test_http_server.py &
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

The Zephyr demo registers a handler for `/sensor`. pvcm-proxy
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

While pvcm-proxy is connected to uart_1, the Zephyr shell is
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
Terminal 1 (Zephyr native_sim_64)     Terminal 2 (pvcm-proxy)        Terminal 3
─────────────────────────────         ──────────────────────         ──────────
zephyr.exe                            pvcm-proxy-test
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
python3 build/workspace/sources/pantavisor/pvcm-proxy/test/test_dbus_service.py &
```

Connect pvcm-proxy with `--dbus-session`:

```bash
echo '{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/Y","transport":"uart","baudrate":921600}}' > /tmp/r.json
/tmp/pvcm-proxy-test --name test --config /tmp/r.json --dbus-session
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

# Start pvcm-proxy
pvcm-proxy --name pvcm-zephyr-shell \
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
pvcm-proxy --name pvcm-zephyr-shell \
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
# Via shell (pvcm-proxy must be running):
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
# Reconnect pvcm-proxy and verify handshake + shell
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

Requires pvcm-proxy started with `--dbus-socket`:

```bash
pvcm-proxy --name pvcm-zephyr-shell \
    --config /storage/trails/current/pvcm-zephyr-shell/run.json \
    --device /dev/ttyRPMSG1 \
    --dbus-socket /volumes/os/docker--pvrun-dbus/system_bus_socket &
```

```bash
# From Zephyr shell (ttyRPMSG0):
pv dbus list
```

### Pass Criteria

- [ ] Returns JSON array of system bus names
- [ ] Contains `"net.connman"`, `"org.pantacor.PvWificonnect"`
- [ ] Response within 1 second

## Test H11: D-Bus Method Call (Hardware)

```bash
pv dbus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner '["net.connman"]'
```

### Pass Criteria

- [ ] Returns unique bus name (e.g. `":1.0"`)
- [ ] No errors
- [ ] Heartbeats continue

## Test H12: D-Bus Signal Subscription (Hardware)

```bash
pv dbus subscribe - /org/freedesktop/DBus org.freedesktop.DBus NameOwnerChanged
```

### Pass Criteria

- [ ] Subscription confirmed
- [ ] Signals appear when services start/stop
- [ ] No interference with heartbeat or HTTP

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
