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
