---
title: Serial Console
sidebar_position: 2
description: Access a Pantavisor device over the serial console — open the debug shell, list and enter containers, query device status, and read logs without any network.
---

The serial console is the most direct access path to a Pantavisor device — it works without any network configuration and shows the full boot sequence from bootloader to Pantavisor startup.

## Hardware Setup

Connect a USB-to-TTY adapter to the device's TX/RX/GND serial pins. Open a terminal emulator on your computer:

```bash
# Linux — adjust device node as needed (ttyUSB0, ttyUSB1, ttyACM0, …)
sudo minicom -b 115200 -D /dev/ttyUSB0

# Alternative
screen /dev/ttyUSB0 115200
```

Refer to your board's hardware manual for the correct UART pins and baud rate. Most Pantavisor images default to **115200 8N1**.

## Boot Sequence and Debug Shell

When the device powers on you will see bootloader output followed by the Linux kernel log, then the Pantavisor banner:

```
_____           _              _
| ___ \         | |            (_)
| |_/ /_ _ _ __ | |_ __ ___   ___ ___  ___  _ __
|  __/ _` | '_ \| __/ _` \ \ / / / __|/ _ \| '__|
| | | (_| | | | | || (_| |\ V /| \__ \ (_) | |
\_|  \__,_|_| |_|\__\__,_| \_/ |_|___/\___/|_|

Pantavisor (TM) — pantavisor.io

To access the debug shell, press <ENTER>.
To exit the shell, type 'exit' or press CTRL+d.
Useful commands:
    * lxc-ls                 list available containers
    * pventer -c <CONTAINER> access a container's shell
```

Press **Enter** to open the debug shell. This is a root shell running in the Pantavisor initramfs — it gives you access to the device before or while containers are starting.

## What You Can Do from the Debug Shell

### List containers

```bash
lxc-ls -f
```

Shows all containers and their LXC state (RUNNING, STOPPED, etc.).

### Enter a container's namespace

```bash
pventer -c sensor-app
```

Drops you into the container's filesystem, process, and network namespaces. Exit with `exit` or `Ctrl-D`.

### Query device status

```bash
pvcontrol ls                            # list containers: status, group, status goal, restart policy
pvcontrol container ls                  # same container list
pvcontrol daemons ls                    # Pantavisor internal daemons
pvcontrol graph ls                      # xconnect service graph
pvcontrol steps show-progress current   # progress of the current revision
pvcontrol buildinfo                     # Pantavisor build info dump
```

### View logs

```bash
tail -f /pv/logs/<revision>/pantavisor/pantavisor.log
tail -f /pv/logs/<revision>/<container>/lxc/console.log
```

The `/pv/` tree (logs, device-id, challenge, metadata, the pv-ctrl socket) is
how the debug shell sees Pantavisor's control directory; inside a container
the same tree is mounted at `/pantavisor/`.

### Find credentials for Pantahub claiming

```bash
cat /pv/device-id       # unique device ID
cat /pv/challenge       # one-time claim token
```

Use these when claiming the device on [hub.pantacor.com](https://hub.pantacor.com).

## Exiting the Debug Shell

Type `exit` or press `Ctrl-D`. Containers start regardless of whether the shell is open, but an open debug shell blocks reboot and power-off — Pantavisor waits for a debug-shell timeout before a reboot proceeds. Pressing **Enter** again reopens the shell at any time.
