# PVCM Integration Plan

Decisions made for Phase 1 implementation. Captures where code lives,
how it builds, and what the first deliverable looks like.

---

## Repositories and Branches

Both repos use branch `feature/pvcm`.

```
pantavisor          (runtime repo)
meta-pantavisor     (Yocto layer)
```

---

## pantavisor repo -- what goes where

### Protocol Header

```
protocol/pvcm_protocol.h        canonical wire format, shared by all
                                 (Linux, U-Boot, Zephyr, FreeRTOS)
```

### pvcm-manager (Linux side)

Part of the pantavisor binary, **not** a standalone daemon. Built when
the `pvcm` feature is enabled:

```cmake
# pantavisor CMakeLists.txt
if(PV_FEATURE_PVCM)
    add_subdirectory(pvcm-manager)
endif()
```

```
pvcm-manager/
    main.c
    pvcm_transport_uart.c
    pvcm_transport_rpmsg.c
    pvcm_health.c
    pvcm_firmware.c
    pvcm_bridge.c
    pvcm_log.c
```

### Zephyr SDK (west module)

```
sdk/zephyr/
    zephyr/module.yml
    CMakeLists.txt
    Kconfig
    include/pantavisor/
        pvcm.h
        pvcm_protocol.h          symlink or copy from protocol/
        pvcm_state.h
    src/
        pvcm_server.c            mandatory: protocol server
        pvcm_state.c             mandatory: flash state r/w
        pvcm_transport_uart.c
        pvcm_transport_rpmsg.c
        pvcm_heartbeat.c         mandatory: heartbeat + crash counter
        pvcm_log_backend.c       mandatory: Zephyr LOG_* -> PV log server
        pvcm_client.c            optional: REST API client
        pvcm_dbus.c              optional: DBus gateway client
        pvcm_events.c            optional: lifecycle callbacks
        pvcm_shell.c             optional: 'pv' shell commands
    samples/
        pvcm-shell/              Phase 1 demo
            CMakeLists.txt
            prj.conf
            src/main.c
```

### FreeRTOS SDK

Later. Same API surface, FreeRTOS primitives. Not Phase 1.

---

## meta-pantavisor repo -- what goes where

### PANTAVISOR_FEATURES

pvcm-manager is controlled via `PANTAVISOR_FEATURES`, same as every
other optional pantavisor component. No standalone recipe.

```python
# classes/pvbase.bbclass -- add to default features
PANTAVISOR_FEATURES ??= "... pvcm"
```

The pantavisor recipe (`recipes-pv/pantavisor/pantavisor_git.bb`)
already maps `PANTAVISOR_FEATURES` to cmake options. Add:

```python
PANTAVISOR_CMAKE_FEATURES += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'pvcm', '-DPV_FEATURE_PVCM=ON', '', d)}"
```

### Distros

Custom distros for RTOS builds, following the same pattern as
`panta-distro` layering on `poky.conf`:

```python
# conf/distro/panta-zephyr.conf
require conf/distro/zephyr.conf          # from meta-zephyr

DISTRO = "panta-zephyr"
DISTRO_NAME = "Pantavisor MCU Zephyr"
DISTRO_VERSION = "027-rc3"
```

Later:

```python
# conf/distro/panta-freertos.conf
DISTRO = "panta-freertos"
DISTRO_NAME = "Pantavisor MCU FreeRTOS"
DISTRO_VERSION = "027-rc3"
```

### Multiconfig

```python
# conf/multiconfig/pv-mcu-zephyr.conf
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-pv-mcu-zephyr-${MCU_ZEPHYR_MACHINE}"
DISTRO = "panta-zephyr"
MACHINE = "${MCU_ZEPHYR_MACHINE}"
ZEPHYR_BOARD = "${MCU_ZEPHYR_BOARD}"
DEPLOY_DIR_IMAGE = "${TMPDIR}/deploy/images/${MACHINE}"
```

The MCU multiconfig is added alongside the default config. The
existing initramfs multiconfig (pv-initramfs-panta) is experimental
and NOT included here:

```
BBMULTICONFIG = "pv-mcu-zephyr"

default              -> panta-distro       -> Linux BSP (A53, normal build)
pv-mcu-zephyr        -> panta-zephyr       -> MCU firmware (M7, arm-none-eabi)
```

Per-MCU-machine TMPDIR via `${MCU_ZEPHYR_MACHINE}` suffix avoids
conflicts when building for multiple MCU targets.

### KAS Structure

#### RTOS-level snippet

```yaml
# kas/pvcm-zephyr.yaml
header:
  version: 16

repos:
  meta-zephyr:
    url: https://github.com/zephyrproject-rtos/meta-zephyr
    branch: main

local_conf_header:
  pvcm-zephyr: |
    BBMULTICONFIG:append = " pv-mcu-zephyr"
    PANTAVISOR_FEATURES:append = " pvcm"
```

#### MCU machine configs

New directory `kas/mcu-machines/` parallel to `kas/machines/` -- MCU
machine configs live separately from Linux machine configs because the
MCU machine is independent of the Linux machine:

```yaml
# kas/mcu-machines/imx8mn-m7.yaml
header:
  version: 16

local_conf_header:
  pvcm-mcu-machine: |
    MCU_ZEPHYR_MACHINE = "imx8mn-m7"
    MCU_ZEPHYR_BOARD = "mimx8mn6_evk/mimx8mn6/m7"
    MCU_ZEPHYR_TRANSPORT = "rpmsg"
```

```yaml
# kas/mcu-machines/rp2040-pico.yaml
header:
  version: 16

local_conf_header:
  pvcm-mcu-machine: |
    MCU_ZEPHYR_MACHINE = "rp2040-pico"
    MCU_ZEPHYR_BOARD = "rpi_pico"
    MCU_ZEPHYR_TRANSPORT = "uart"
```

#### Usage

```bash
# Build Linux BSP + MCU firmware for Variscite i.MX8MN with M7
kas build kas/scarthgap.yaml:kas/machines/imx8mn-var-som.yaml:kas/bsp-base.yaml:kas/pvcm-zephyr.yaml:kas/mcu-machines/imx8mn-m7.yaml
```

### Kconfig Menu

New "MCU Containers" menu in the KAS Kconfig, following the existing
pattern of choice -> KAS_INCLUDE_* string mapping:

```kconfig
menu "MCU Containers"

config PVCM_ENABLE
    bool "Enable MCU container support (PVCM)"
    default n
    help
      Build MCU firmware as a Pantavisor container alongside the
      Linux BSP. Adds pvcm-manager to pantavisor and builds the
      selected RTOS firmware via multiconfig.

choice
    prompt "MCU RTOS"
    depends on PVCM_ENABLE
    default PVCM_RTOS_ZEPHYR

config PVCM_RTOS_ZEPHYR
    bool "Zephyr RTOS"

config PVCM_RTOS_FREERTOS
    bool "FreeRTOS"

endchoice

choice
    prompt "MCU Machine"
    depends on PVCM_ENABLE

config PVCM_MCU_IMX8MN_M7
    bool "i.MX8MN Cortex-M7 (Variscite, internal RPMsg)"
    depends on PVCM_RTOS_ZEPHYR
    help
      Internal M7 core on i.MX8MN SoC. Transport: RPMsg.
      Zephyr board: mimx8mn6_evk/mimx8mn6/m7

config PVCM_MCU_RP2040_PICO
    bool "RP2040 Pico (external USB UART)"
    depends on PVCM_RTOS_ZEPHYR
    help
      Raspberry Pi Pico via USB. Transport: UART over /dev/ttyACM*.
      Zephyr board: rpi_pico

endchoice

endmenu

config KAS_INCLUDE_PVCM
    string
    default "kas/pvcm-zephyr.yaml" if PVCM_RTOS_ZEPHYR && PVCM_ENABLE

config KAS_INCLUDE_PVCM_MCU
    string
    default "kas/mcu-machines/imx8mn-m7.yaml" if PVCM_MCU_IMX8MN_M7
    default "kas/mcu-machines/rp2040-pico.yaml" if PVCM_MCU_RP2040_PICO
```

### MCU Container Recipes

Under `recipes-containers/`, following the naming pattern
`pvcm-{rtos}-{name}`:

```
recipes-containers/
    pvcm-zephyr-shell/
        pvcm-zephyr-shell.bb       Phase 1: M7 shell demo
```

The recipe points meta-zephyr at the sample source in
`pantavisor/sdk/zephyr/samples/pvcm-shell/`.

Future containers follow the same pattern:

```
recipes-containers/
    pvcm-zephyr-shell/             Zephyr shell demo
    pvcm-zephyr-sensor/            Zephyr sensor example
    pvcm-freertos-hello/           FreeRTOS minimal example
    ...
```

### BSP Integration

BSP bbappend adds MCU firmware ELF to the BSP container via mcdepends:

```python
do_image[mcdepends] += "mc::pv-mcu-zephyr:pvcm-zephyr-shell:do_deploy"
```

---

## Phase 1 Target: Variscite i.MX8MN M7

### Combo

```
Linux machine:   imx8mn-var-som     (A53, kas/machines/imx8mn-var-som.yaml)
MCU machine:     imx8mn-m7          (M7, kas/mcu-machines/imx8mn-m7.yaml)
RTOS:            Zephyr             (kas/pvcm-zephyr.yaml)
Transport:       RPMsg              (internal M core)
```

### RTOS: Zephyr

Zephyr is the right choice for i.MX8MN M7:
- NXP is Zephyr platinum member, M7 support is upstream
- Board: `mimx8mn6_evk/mimx8mn6/m7`
- RPMsg/OpenAMP mature in Zephyr for i.MX8 M-cores
- West module system fits the SDK naturally
- meta-zephyr provides Yocto multiconfig integration

FreeRTOS SDK comes later as follow-up.

### The Shell Demo

One sample, not two. The shell demo **is** the minimal example.
Heartbeat, log backend, and protocol server are mandatory -- they
start automatically with `CONFIG_PANTAVISOR=y`. The shell is the
only optional module enabled for the demo.

```c
/* sdk/zephyr/samples/pvcm-shell/src/main.c */
#include <pantavisor/pvcm.h>

void main(void) {
    /* pvcm_server, pvcm_heartbeat, pvcm_log_backend already running */
    /* shell commands registered via CONFIG_PANTAVISOR_SHELL=y */
}
```

```kconfig
# sdk/zephyr/samples/pvcm-shell/prj.conf
CONFIG_PANTAVISOR=y
CONFIG_PANTAVISOR_TRANSPORT_RPMSG=y
CONFIG_PANTAVISOR_SHELL=y
```

### What the Demo Validates

- PVCM protocol handshake over RPMsg (internal M7)
- Heartbeat stream (5s interval, automatic)
- Log forwarding (Zephyr LOG_* -> PV log server)
- Interactive `pv status` / `pv containers` over ttyRPMSG
- pvcm-manager probe and health monitoring on Linux side

---

## pvr --type mcu

pvr needs a new source type `mcu` for creating MCU container pvrexports.
The pattern follows the existing `--type rootfs` but instead of squashing
a rootfs, it packages a firmware ELF.

### Changes to pvr repo

**models/sourcetypes.go** -- add `SourceTypeMcu = "mcu"`

**libpvr/appmculib.go** -- new file, implements:
- `AddMcuApp(p, app)` -- copies firmware ELF to container dir, writes
  src.json with MCU-specific fields
- `InstallMcuApp(p, app, manifest)` -- generates run.json from template

**libpvr/applib.go** -- add `case models.SourceTypeMcu:` in both
`AddApplication` and `InstallApplication` switch statements

**templates/builtin-mcu.go** -- new template handler `builtin-mcu`
that generates run.json for MCU containers from template args

**templates/templates.go** -- register `"builtin-mcu": BuiltinMcuHandler`

**cmd/app/appadd.go** -- add `models.SourceTypeMcu` to --type help text

### CLI usage

```bash
pvr app add \
    --type mcu \
    --from /path/to/firmware.elf \
    --arg-json mcu-args.json \
    --group root \
    mcu-display
```

### args.json for MCU containers

The args.json carries MCU-specific fields that the builtin-mcu template
uses to generate run.json:

```json
{
    "PV_MCU_DEVICE": "display",
    "PV_MCU_TRANSPORT": "rpmsg",
    "PV_MCU_BAUDRATE": 921600,
    "PV_MCU_HEALTH_TIMEOUT": 30,
    "PV_MCU_MAX_RESTARTS": 3,
    "PV_SERVICES_REQUIRED": [
        {
            "name": "system-bus",
            "type": "dbus",
            "interface": "org.freedesktop.NetworkManager",
            "target": "/run/dbus/system_bus_socket"
        }
    ]
}
```

### Generated run.json

The builtin-mcu template generates:

```json
{
    "#spec": "service-manifest-run@1",
    "name": "mcu-display",
    "type": "mcu",
    "mcu": {
        "device": "display",
        "transport": "rpmsg",
        "baudrate": 921600
    },
    "firmware": "firmware.elf",
    "policy": {
        "tryboot": {
            "health_timeout_s": 30,
            "on_failure": "rollback"
        },
        "operational": {
            "on_crash": "restart",
            "max_restarts": 3
        }
    }
}
```

services.json is handled the same way as Linux containers -- copied
directly if provided.

### bbclass usage (meta-pantavisor)

The container-pvrexport or a new mcu-pvrexport bbclass calls pvr:

```bash
pvr app add \
    --force \
    --type mcu \
    --from "${DEPLOY_DIR_IMAGE}/pvcm-zephyr-shell.elf" \
    --arg-json ${WORKDIR}/${PN}.args.json \
    --group root \
    ${PN}
```

---

## Build Status and Known Issues

### Zephyr multiconfig build (2026-03-22)

The multiconfig build parses and builds successfully (1398/1399 tasks).
The single failure is `do_configure` for `pvcm-zephyr-shell` because
the Zephyr board name `mimx8mn6_evk` doesn't exist in Zephyr 3.6.0
(meta-zephyr scarthgap ships Zephyr 3.6.0, board naming changed in
newer versions).

**TODO:** find the correct board name for i.MX8MN M7 in Zephyr 3.6.0,
or check if a newer meta-zephyr branch is needed.

### meta-zephyr

- Official repo: `git://git.yoctoproject.org/meta-zephyr`
- Branch: `scarthgap` (compat: kirkstone, scarthgap)
- Has two sublayers: `meta-zephyr-core` and `meta-zephyr-bsp`
- Distro: `zephyr` (TCLIBC=newlib)
- No i.MX8MN machine -- we provide `conf/machine/imx8mn-m7.conf`
- `zephyr-sample` bbclass is what recipes inherit (not `zephyr-app`)

---

## Work Order

### pantavisor repo (feature/pvcm)

1. [done] `protocol/pvcm_protocol.h` -- wire format, opcodes, structs
2. [done] `sdk/zephyr/` -- west module skeleton, Kconfig, mandatory modules
3. [done] `sdk/zephyr/samples/pvcm-shell/` -- Phase 1 demo app
4. `pvcm-manager/` -- transport, probe, health, log forwarding
5. `src/bootstate.c` refactor -- pluggable backend abstraction
6. `src/bootstate_mcu.c` -- MCU backend

### pvr repo (feature/pvcm)

1. `models/sourcetypes.go` -- add SourceTypeMcu
2. `libpvr/appmculib.go` -- AddMcuApp, InstallMcuApp
3. `libpvr/applib.go` -- wire mcu case in Add/Install switches
4. `templates/builtin-mcu.go` -- MCU run.json template handler
5. `templates/templates.go` -- register builtin-mcu handler
6. `cmd/app/appadd.go` -- add mcu to --type help

### meta-pantavisor repo (feature/pvcm)

1. [done] `conf/distro/panta-zephyr.conf` -- Zephyr distro
2. [done] `conf/multiconfig/pv-mcu-zephyr.conf` -- MCU multiconfig
3. [done] `kas/pv-mcu-zephyr.yaml` -- RTOS-level KAS snippet
4. [done] `kas/mcu-machines/imx8mn-m7.yaml` -- M7 MCU machine config
5. [done] `kas/mcu-machines/rp2040-pico.yaml` -- Pico MCU machine config
6. [done] `Kconfig` -- add MCU Containers menu
7. [done] `conf/machine/imx8mn-m7.conf` -- Zephyr MCU machine
8. [done] `recipes-pv/pantavisor/pantavisor_git.bb` -- wire PV_FEATURE_PVCM cmake flag
9. [done] `recipes-containers/pvcm-zephyr-shell/` -- demo recipe
10. [todo] Fix Zephyr board name for i.MX8MN M7 (Zephyr 3.6.0 compat)
11. [todo] BSP integration -- mcdepends to pull MCU ELF into BSP container
12. [todo] MCU pvrexport bbclass using pvr --type mcu
