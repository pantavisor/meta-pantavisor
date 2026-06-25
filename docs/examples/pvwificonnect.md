---
sidebar_position: 2
---
# pvwificonnect — WiFi Provisioning Container

`pvwificonnect` ships as a **core container** in the starter image
(`PVROOT_CONTAINERS_CORE` in `recipes-pv/images/pantavisor-starter.bb`). It is a
Go network-provisioning service ([gitlab.com/pantacor/pvwificonnect](https://gitlab.com/pantacor/pvwificonnect))
that lets a headless device be joined to a WiFi network without a console: it
brings up an access point / captive portal, can tether AP clients to an existing
uplink, and watches connectivity so it can re-provision after a drop.

## What it brings to the system

| Feature | Description |
|---------|-------------|
| **Access point** | Broadcasts a setup SSID (default `pvwificonnect` / `1234567890`) so a phone/laptop can connect to the device. |
| **Captive portal** | Redirects connecting clients to a web setup page (opt-in via `captive_portal`). |
| **Internet tethering** | Shares the device's uplink (`eth0`, `wwan0`, …) to AP clients (opt-in via `tethering`). |
| **Auto mode** | Picks portal vs. tethering automatically based on connectivity (`auto_mode`, on by default). |
| **Connection watcher** | Background loop that re-triggers AP/tethering setup when connectivity is lost (`watcher`). |
| **Pluggable backend** | Talks to the network stack over D-Bus (`org.pantacor.PvWificonnect`); adapts to whichever backend container is present. |

It is built three ways in this layer:

| Recipe | Produces |
|--------|----------|
| `recipes-containers/pantavisor/pvwificonnect_v1.7.0.bb` | The pvrexport container (this doc). |
| `recipes-containers/pantavisor/pvwificonnect-app_v1.7.0.bb` | The `pvwificonnect` + `pvwificonnect-cli` binaries built from source. |
| `recipes-containers/pantavisor/pv-pvwificonnect_v1.7.0.bb` | The prebuilt Docker-image variant. |

## Network backend dependency

`pvwificonnect` does not manage WiFi hardware itself — it drives a backend over
the **host D-Bus** (imported via `os:/pvrun/dbus:/var/run/dbus`, see
`args.json`). The starter image pairs it with the ConnMan backend:

```bitbake
PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi"
```

| Backend container | Stack | AP gateway IP |
|-------------------|-------|---------------|
| `pv-alpine-connman` (default here) | ConnMan tethering API + dnsmasq | `192.168.0.1` |
| Debian / NetworkManager | NM "shared" connection profiles | `10.42.0.1` |

If neither backend is running, the service waits at startup up to
`wait_time_in_sec` for D-Bus readiness. The board must also have working WiFi
firmware and a `wlanN` interface — see the board flashing guides
(e.g. [Verdin iMX8MM](../how-to-install/boards/verdin-imx8mm.md),
[Colibri iMX6ULL](../how-to-install/boards/colibri-imx6ull.md)) for enabling the
WiFi DTB and firmware.

## Configuration

Runtime settings live in `/var/pvwificonnect/config.json` inside the container.
The layer ships this overlay
(`recipes-containers/pantavisor/pvwificonnect/pvwificonnect-config/var/pvwificonnect/config.json`):

```json
{
    "ap": {
        "ssid": "pvwificonnect",
        "password": "1234567890"
    },
    "auto_mode": true,
    "wait_time_in_sec": 60,
    "watcher": true,
    "watcher_interval": "1m"
}
```

### config.json keys

| Key | Meaning | Default |
|-----|---------|---------|
| `ap.ssid` | SSID broadcast by the access point | `pvwificonnect` |
| `ap.password` | AP password | `1234567890` |
| `network.ssid` / `network.password` | Pre-seed credentials for an existing network to join | unset |
| `captive_portal` | Redirect AP clients to a web setup page | `false` |
| `tethering` | Share the device uplink to AP clients | `false` |
| `auto_mode` | Auto-select portal vs. tethering from connectivity | `true` |
| `uplink_interface` | Preferred uplink (`eth0`, `wwan0`, …) | auto-detected |
| `wait_time_in_sec` | D-Bus readiness timeout at startup | `60` |
| `watcher` | Background connectivity monitor | `false` |
| `watcher_interval` | Watcher check frequency (Go duration) | `1m` |
| `watcher_max_retries` | Failures before the watcher backs off | `3` |

> Change the default AP SSID/password before shipping a product image — the
> `1234567890` default is for bring-up only.

### Environment variables

Set in the container's Docker config (`recipes-containers/pantavisor/pvwificonnect/config.json`):

| Variable | Meaning | Default |
|----------|---------|---------|
| `PV_WIFI_CONNECT_WATCHER` | Enable the connection watcher | `false` |
| `PV_WIFI_CONNECT_INTERVAL` | Watcher interval (Go duration) | `1m` |
| `PV_WIFI_CONNECT_MAX_RETRIES` | Max consecutive watcher failures | `3` |

### Container runtime args

`args.json` grants the container the capabilities and group it needs:

```json
{
    "PV_GROUP": "platform",
    "PV_LXC_CAP_KEEP": [
        "block_suspend", "wake_alarm", "sys_time",
        "net_admin net_raw net_bind_service"
    ],
    "PV_RESTART_POLICY": "system",
    "PV_VOLUME_IMPORTS": ["os:/pvrun/dbus:/var/run/dbus"]
}
```

## Using it

1. **Boot a device** running the starter image with both `pvwificonnect` and a
   network backend (`pv-alpine-connman`). The service starts in the `platform`
   group.
2. **Join the setup AP** — from a phone/laptop connect to the `ap.ssid`
   (default `pvwificonnect`, password `1234567890`). The backend hands out an
   address on its gateway subnet (`192.168.0.x` for ConnMan).
3. **Provision** — with `captive_portal` enabled, opening a browser redirects to
   the setup page where you select the home network and enter credentials.
   Alternatively, pre-seed `network.ssid`/`network.password` in `config.json` so
   the device joins on first boot with no interaction.
4. **Stay connected** — with `watcher` on, the service re-runs AP/tethering
   setup whenever connectivity drops.

The `pvwificonnect-cli` binary (installed to `/usr/bin` by `pvwificonnect-app`)
is available inside the container for inspecting and driving the service over its
D-Bus interface.

## Building

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pvwificonnect
```

Output: `build/tmp-scarthgap/deploy/images/<machine>/pvwificonnect.pvrexport.tgz`.
Because it is in `PVROOT_CONTAINERS_CORE`, a full `pantavisor-starter` build
already includes it.

## Related

- [Container Development](../how-to-build/container-development.md) — authoring and packaging containers
- [pvwificonnect upstream](https://gitlab.com/pantacor/pvwificonnect) — service source and backend details
