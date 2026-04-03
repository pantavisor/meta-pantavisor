# PVCM Development Guide

Development workflows for iterating on PVCM (Pantavisor Container MCU)
firmware and proxy. Two paths: native_sim for fast protocol iteration,
and real hardware (i.MX8MN VAR-SOM) for end-to-end validation.

## 1. native_sim Iteration

Fast local development using Zephyr's native_sim_64 target. The Zephyr
firmware runs as a Linux executable with PTY-based UART transport.
Turnaround: seconds.

### Build

```bash
# Build Zephyr firmware (native_sim_64)
kas build kas/scarthgap.yaml:kas/bsp-base.yaml:kas/pv-mcu-zephyr.yaml:kas/mcu-machines/native-sim.yaml \
    --target mc:pv-mcu-zephyr:pvcm-zephyr-shell

# Build pvcm-run for the host
PV=build/workspace/sources/pantavisor
gcc -o /tmp/pvcm-run-test \
    $PV/pvcm-run/main.c \
    $PV/pvcm-run/pvcm_config.c \
    $PV/pvcm-run/pvcm_transport_uart.c \
    $PV/pvcm-run/pvcm_transport_rpmsg.c \
    $PV/pvcm-run/pvcm_protocol.c \
    $PV/pvcm-run/pvcm_bridge.c \
    $PV/pvcm-run/pvcm_dbus_bridge.c \
    $PV/pvcm-run/pvcm_fs_bridge.c \
    $PV/pvcm-run/pvcm_sendq.c \
    -I$PV -levent $(pkg-config --cflags --libs dbus-1)
```

The Zephyr executable is at:
```
build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/work/x86_64-yocto-linux/pvcm-zephyr-shell/3.6.0+git/build/zephyr/zephyr.exe
```

### Run

```bash
# Terminal 1: start Zephyr (creates two PTYs: uart for shell, uart_1 for PVCM)
EXE=build/tmp-panta-zephyr-pv-mcu-zephyr-native-sim-glibc/work/x86_64-yocto-linux/pvcm-zephyr-shell/3.6.0+git/build/zephyr/zephyr.exe
/lib64/ld-linux-x86-64.so.2 $EXE

# Note the PTY paths from output (e.g. /dev/pts/3 and /dev/pts/4)

# Terminal 2: connect pvcm-run to uart_1 PTY
echo '{"name":"test","type":"mcu","mcu":{"device":"/dev/pts/4","transport":"uart","baudrate":921600}}' > /tmp/r.json
/tmp/pvcm-run-test --name test --config /tmp/r.json

# With D-Bus gateway (session bus):
/tmp/pvcm-run-test --name test --config /tmp/r.json --dbus-session

# With filesystem share:
/tmp/pvcm-run-test --name test --config /tmp/r.json --fs-share storage=/tmp/my-share

# All gateways:
/tmp/pvcm-run-test --name test --config /tmp/r.json --dbus-session --fs-share storage=/tmp/my-share

# Terminal 3: interactive shell on uart PTY
screen /dev/pts/3
```

### Iterate

Edit source, recompile pvcm-run with gcc (instant), or rebuild the
Zephyr target with kas (~30s). No cleanup needed between runs.

### D-Bus Testing (native_sim)

Start a test D-Bus service on the session bus:

```bash
python3 build/workspace/sources/pantavisor/pvcm-run/test/test_dbus_service.py &
```

Then from the Zephyr shell:

```
pv dbus list
pv dbus call org.pantavisor.TestService /test org.pantavisor.TestService Echo [hello]
pv dbus subscribe org.pantavisor.TestService /test org.pantavisor.TestService Tick
```

### Filesystem Testing (native_sim)

Start pvcm-run with `--fs-share`:

```bash
mkdir -p /tmp/my-share && echo "hello" > /tmp/my-share/test.txt
/tmp/pvcm-run-test --name test --config /tmp/r.json --fs-share storage=/tmp/my-share
```

Then from the Zephyr shell:

```
pv mount storage /storage
fs ls /storage
fs cat /storage/test.txt
```

## 2. Hardware Setup (i.MX8MN VAR-SOM)

### Board: Variscite VAR-SOM-MX8M-NANO

The board has a Cortex-M7 core that communicates with Linux via RPMsg
over shared DDR memory. Two RPMsg channels are created: ttyRPMSG0
(Zephyr shell) and ttyRPMSG1 (PVCM protocol).

### U-Boot Configuration

The M7 requires a DTB with remoteproc support. The default Variscite
DTB uses a dummy clock for the M7 core — you must select the M7-enabled
DTB variant in U-Boot:

```
# In U-Boot console (serial or HDMI):
setenv localargs fdtfile=freescale/imx8mn-var-som-symphony-m7.dtb
saveenv
reset
```

This sets the device tree to the M7-enabled variant that has:
- `IMX8MN_CLK_M7_CORE` clock (not `CLK_DUMMY` — avoids AXI bus hang)
- Remoteproc node with reserved memory regions
- RPMsg/virtio channels

**Without this, remoteproc will either not work or hard-hang the
system.** The default DTB gates the M7 clock.

### SSH Access

```bash
SSH="ssh -p 8222 -i ~/.ssh/id_ed25519-bot _pv_@<device-ip>"
```

No `scp` — use pipe transfers: `cat file | $SSH 'cat > /path'`

## 3. Building for Hardware

### BSP Build (kernel + initramfs + DTBs)

Look up the KAS config in `.github/machines.json` for the machine,
replace the release target with `kas/with-workspace.yaml`:

```bash
# BSP build with workspace (includes pvcm-run in initramfs)
./kas-container build \
    kas/machines/imx8mn-var-som.yaml:kas/scarthgap.yaml:kas/scarthgap-var.yaml:kas/bsp-base.yaml:kas/with-workspace.yaml \
    -- pantavisor-bsp
```

Output: `build/tmp-scarthgap/deploy/images/imx8mn-var-som/pantavisor-bsp-imx8mn-var-som.pvrexport.tgz`

### MCU Firmware Build (Zephyr for M7)

```bash
kas build \
    kas/scarthgap.yaml:kas/machines/imx8mn-var-som.yaml:kas/bsp-base.yaml:kas/pv-mcu-zephyr.yaml:kas/mcu-machines/imx8mn-m7.yaml \
    --target mc:pv-mcu-zephyr:pvcm-zephyr-shell
```

Output ELF: `build/tmp-panta-zephyr-pv-mcu-zephyr-imx8mn-m7-glibc/work/imx8mn-m7-yocto-elf/pvcm-zephyr-shell/*/build/zephyr/zephyr.elf`

### Quick Zephyr Iteration (west build)

For fast firmware iteration without KAS:

```bash
cd build/workspace/sources/pantavisor/sdk/zephyr-sdk
source zephyr/zephyr-env.sh
west build -b mimx8mn_evk -d build-test \
    ../zephyr/samples/pvcm-shell -- \
    -DBOARD_ROOT=$(pwd)/../zephyr \
    -DZEPHYR_EXTRA_MODULES=$(pwd)/../zephyr
```

This takes ~30s and produces `build-test/zephyr/zephyr.elf`.

## 4. Deploying to Device

### Deploy BSP (pvr post — causes reboot)

Use pvr to push BSP updates over Pantahub. Only needed when changing
kernel, DTBs, initramfs (pvcm-run binary), or pantavisor itself.

```bash
mkdir -p /tmp/pvr-deploy && cd /tmp/pvr-deploy
pvr clone asacasa/<device-nick>
cd <device-nick>

# Merge new BSP
pvr merge /path/to/pantavisor-bsp-imx8mn-var-som.pvrexport.tgz

# IMPORTANT: verify changes BEFORE checkout (diff is empty after checkout)
pvr diff

# Apply, sign, commit, push
pvr checkout
pvr sig up
pvr add && pvr commit
pvr post
```

The device downloads the update, reboots, and applies the new revision.
Monitor: `$SSH 'ls -la /storage/trails/current'`

### Deploy MCU Firmware (no reboot)

Upload and restart M7 firmware without rebooting. Use this for Zephyr
SDK and sample app changes — much faster than BSP rebuild.

```bash
# Upload firmware to device storage
cat zephyr.elf | $SSH 'cat > /storage/fw.elf'

# Set firmware search path (read-only /lib/firmware, use /storage/)
$SSH 'echo -n /storage > /sys/module/firmware_class/parameters/path'
$SSH 'echo fw.elf > /sys/class/remoteproc/remoteproc0/firmware'

# Stop (if running) and start
$SSH 'echo stop > /sys/class/remoteproc/remoteproc0/state'
sleep 3  # MUST reach "offline" before changing firmware
$SSH 'echo start > /sys/class/remoteproc/remoteproc0/state'
sleep 3

# Verify
$SSH 'cat /sys/class/remoteproc/remoteproc0/state'  # "running"
$SSH 'ls /dev/ttyRPMSG*'  # ttyRPMSG0 + ttyRPMSG1
```

### Deploy MCU Container via BSP (production path)

For production, MCU firmware is packaged as a pvrexport and included
in the BSP image. Add it to `PVROOT_CONTAINERS_CORE` with the `mc:`
prefix:

```python
PVROOT_CONTAINERS_CORE += "mc:pv-mcu-zephyr:pvcm-zephyr-shell"
```

The firmware is then deployed as part of the BSP revision and managed
by pantavisor alongside other containers. The `args.json` configures
remoteproc, transport, and device:

```json
{
    "PV_MCU_DEVICE": "display",
    "PV_MCU_TRANSPORT": "rpmsg",
    "PV_MCU_REMOTEPROC": "remoteproc0",
    "PV_STATUS_GOAL": "MOUNTED"
}
```

## 5. Running and Testing

### Start pvcm-run

```bash
# Basic (HTTP gateway only)
$SSH 'pvcm-run --name pvcm-test --transport rpmsg --device /dev/ttyRPMSG1 &'

# With D-Bus gateway (connects to system bus)
$SSH 'pvcm-run --name pvcm-test --transport rpmsg --device /dev/ttyRPMSG1 \
    --dbus-socket /volumes/os/docker--pvrun-dbus/system_bus_socket &'

# Check proxy log
$SSH 'cat /tmp/pvcm-run.log'
```

### Interactive Shell Testing

```bash
# Start reading shell output, then send commands
$SSH 'cat /dev/ttyRPMSG0 > /tmp/rpmsg_out.txt 2>&1 &
CATPID=$!; sleep 1
echo "pv status" > /dev/ttyRPMSG0; sleep 3
echo "pv dbus list" > /dev/ttyRPMSG0; sleep 5
echo "pv http /cgi-bin/logs" > /dev/ttyRPMSG0; sleep 10
kill $CATPID 2>/dev/null
cat /tmp/rpmsg_out.txt'
```

### HTTP Gateway Test

```bash
# MCU → Linux (Zephyr calls pv-ctrl)
$SSH 'echo "pv http /cgi-bin/logs" > /dev/ttyRPMSG0'

# Linux → MCU (curl calls MCU handler)
$SSH 'printf "GET /sensor HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -w 5 127.0.0.1 18081'
```

### D-Bus Gateway Test

```bash
# List services on system bus
$SSH 'echo "pv dbus list" > /dev/ttyRPMSG0'

# Call a method (bare args — Zephyr shell strips quotes)
$SSH 'echo "pv dbus call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner [net.connman]" > /dev/ttyRPMSG0'

# Subscribe to signals
$SSH 'echo "pv dbus subscribe org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameOwnerChanged" > /dev/ttyRPMSG0'
```

### Monitor

```bash
# pvcm-run log
$SSH 'cat /tmp/pvcm-run.log'

# Pantavisor container logs via HTTP (port 12368, Tailscale IP)
curl "http://<tailscale-ip>:12368/cgi-bin/logs?rev=N&source=pvcm-zephyr-shell"

# All logs
curl "http://<tailscale-ip>:12368/cgi-bin/logs?rev=N&n=+0"
```

## When to Use Which

| Change | Deploy Method | Turnaround |
|--------|---------------|------------|
| Protocol structs (pvcm_protocol.h) | native_sim (gcc + run) | seconds |
| pvcm-run C code | native_sim (gcc + run) | seconds |
| Zephyr SDK / shell commands | native_sim (kas) or west build + upload | 30s |
| D-Bus bridge logic | native_sim (gcc + session bus) | seconds |
| Zephyr sample app (firmware) | west build + upload to /storage/ | 30s |
| pvcm-run in initramfs | BSP build + pvr post (reboot) | ~10 min |
| Kernel / DTB changes | BSP build + pvr post (reboot) | ~10 min |
| MCU container (production) | BSP build with PVROOT_CONTAINERS_CORE | ~10 min |

## Key Paths

| Path | Description |
|------|-------------|
| `build/workspace/sources/pantavisor/pvcm-run/` | pvcm-run source |
| `build/workspace/sources/pantavisor/sdk/zephyr/` | Zephyr SDK (client lib + shell) |
| `build/workspace/sources/pantavisor/protocol/` | Protocol header (canonical copy) |
| `build/workspace/sources/pantavisor/sdk/zephyr/include/pantavisor/` | Zephyr SDK headers (protocol copy synced here) |
| `build/workspace/sources/pantavisor/sdk/zephyr/samples/pvcm-shell/` | Zephyr sample app |
| `build/workspace/sources/pantavisor/sdk/zephyr-sdk/` | Zephyr SDK + west workspace |

## Architecture

```
                    native_sim (PTY)                  Hardware (RPMsg)
                    ────────────────                  ────────────────
Zephyr firmware     zephyr.exe (Linux process)        Cortex-M7 (remoteproc)
  Shell channel     uart → /dev/pts/X                 ttyRPMSG0
  PVCM channel      uart_1 → /dev/pts/Y              ttyRPMSG1

pvcm-run          /tmp/pvcm-run-test              /usr/bin/pvcm-run
  Transport         UART (PTY)                        RPMsg (ttyRPMSG1)
  HTTP bridge       localhost:18080 ↔ MCU             pv-ctrl ↔ MCU
  D-Bus bridge      session bus (--dbus-session)      system bus (--dbus-socket)
```

## Hardware Notes

### i.MX8MN M7 Memory Map

- DDR: `0x40000000–0x7FFFFFFF` (1 GB)
- M7 reserved: `0x7E000000` (16 MiB, top of RAM)
- Vrings: `0x40000000`, `0x40008000`
- Resource table: `0x400FF000` (must match Zephyr linker script)

### Zephyr Board: mimx8mn_evk

Custom board at `sdk/zephyr/boards/arm/mimx8mn_evk/` (no upstream
Zephyr board for i.MX8MN M7 yet). Key configs:

```kconfig
CONFIG_IPM_IMX_MAX_DATA_SIZE_4=y   # MU register index matches Linux DTB
CONFIG_OPENAMP_MASTER=n            # M7 is remote/device role
CONFIG_OPENAMP_RSC_TABLE_NUM_RPMSG_BUFF=32  # prevent TX vring exhaustion
```
