# PVCM Protocol Test Plan

End-to-end testing of the PVCM protocol between pvcm-proxy (Linux)
and Zephyr native_sim_64 over PTY.

## Prerequisites

Build the native_sim_64 Zephyr target:

```bash
kas build kas/scarthgap.yaml:kas/bsp-base.yaml:kas/pv-mcu-zephyr.yaml:kas/mcu-machines/native-sim.yaml --target mc:pv-mcu-zephyr:pvcm-zephyr-shell
```

Build pvcm-proxy for the host:

```bash
PV=build/workspace/sources/pantavisor
gcc -o /tmp/pvcm-proxy-test \
    $PV/pvcm-proxy/main.c \
    $PV/pvcm-proxy/pvcm_config.c \
    $PV/pvcm-proxy/pvcm_transport_uart.c \
    $PV/pvcm-proxy/pvcm_protocol.c \
    -I$PV -include $PV/protocol/pvcm_protocol.h
```

## Test 1: HELLO Handshake + Heartbeat

Validates the full PVCM protocol stack: frame encoding/decoding,
CRC32, HELLO/HELLO_RESP handshake, and heartbeat monitoring.

### Start Zephyr (MCU side)

```bash
EXE=$(ls -t build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/deploy/images/native-sim/pvcm-zephyr-shell-native-sim-*.elf | head -1)

# If zephyr.exe not in deploy, find it in work dir:
# EXE=build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/work/x86_64-yocto-linux/pvcm-zephyr-shell/3.6.0+git/build/zephyr/zephyr.exe

/lib64/ld-linux-x86-64.so.2 $EXE --rt
```

Expected output:
```
uart connected to pseudotty: /dev/pts/X
uart_1 connected to pseudotty: /dev/pts/Y     <- PVCM PTY
*** Booting Zephyr OS build v3.6.0 ***
[00:00:00.000,000] <inf> pvcm_server: PVCM server starting (protocol v1)
[00:00:00.000,000] <inf> pvcm_uart: PVCM UART transport ready on uart_1
[00:00:00.000,000] <inf> pvcm_server: transport ready, entering recv loop
[00:00:00.000,000] <inf> pvcm_heartbeat: PVCM heartbeat starting (5000 ms interval)
```

Note the `uart_1` PTY path (`/dev/pts/Y`) — this is the PVCM UART.
The `uart` PTY (`/dev/pts/X`) is the shell/console.

### Connect pvcm-proxy (Linux side)

In a second terminal, use the `uart_1` PTY path:

```bash
cat > /tmp/pvcm-run.json <<EOF
{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/Y","transport":"uart","baudrate":921600}}
EOF

/tmp/pvcm-proxy-test --name test --config /tmp/pvcm-run.json
```

### Expected Result

```
[pvcm-proxy] starting for MCU 'test'
[pvcm-proxy] config: device=/dev/pts/Y transport=uart baudrate=921600 firmware=(none)
[pvcm-proxy] UART opened: /dev/pts/Y @ 921600 baud
[pvcm-proxy] sending HELLO
[pvcm-proxy] MCU connected: protocol=v1 fw=v1 baudrate=921600
[pvcm-proxy] entering main loop
[pvcm-proxy] heartbeat: status=OK uptime=5s crashes=0
[pvcm-proxy] heartbeat: status=OK uptime=10s crashes=0
...
```

### Pass Criteria

- [ ] HELLO handshake succeeds (`MCU connected: protocol=v1`)
- [ ] Heartbeats arrive every ~5 seconds
- [ ] Health status is OK
- [ ] Crash count is 0
- [ ] Ctrl+C cleanly shuts down both sides

## Test 2: Shell Access

While pvcm-proxy is connected to uart_1, the Zephyr shell remains
accessible on uart (uart0).

### Connect to shell

```bash
# Use the uart PTY (not uart_1)
screen /dev/pts/X
```

### Expected Result

```
uart:~$ pv status
PVCM protocol v1
Transport: UART
Heartbeat: 5000 ms

uart:~$ pv heartbeat
Uptime: 42 s
```

### Pass Criteria

- [ ] Shell prompt appears on uart0 PTY
- [ ] `pv status` shows protocol version
- [ ] `pv heartbeat` shows uptime
- [ ] Shell does not interfere with PVCM protocol on uart1

## Architecture

```
Terminal 1 (Zephyr native_sim_64)     Terminal 2 (pvcm-proxy)
─────────────────────────────         ──────────────────────
zephyr.exe --rt                       pvcm-proxy-test
  uart0 (/dev/pts/X) → shell            reads from /dev/pts/Y
  uart1 (/dev/pts/Y) → PVCM             writes to /dev/pts/Y
    ├── server: HELLO_RESP
    ├── heartbeat: every 5s          ← heartbeat: status=OK
    └── log: forwarded               ← [MCU/INF] sensor: temp=22.4C
```

## UART Configuration (native_sim_64)

The board overlay `boards/native_sim_64.conf` configures:

```kconfig
CONFIG_UART_NATIVE_POSIX_PORT_1_ENABLE=y   # enable uart_1
CONFIG_PANTAVISOR_UART_DEVICE="uart_1"     # PVCM transport on uart_1
CONFIG_NATIVE_SIM_SLOWDOWN_TO_REAL_TIME=y  # wall-clock sync
```

UART0 (shell) uses default stdin/stdout or own PTY.
UART1 (PVCM) always uses its own bidirectional PTY.
