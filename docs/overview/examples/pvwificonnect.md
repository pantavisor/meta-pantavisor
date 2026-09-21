---
sidebar_position: 2
---
# pvwificonnect — WiFi Provisioning Container

`pvwificonnect` ships as a **core container** in the starter image
(`PVROOT_CONTAINERS_CORE` in `recipes-pv/images/pantavisor-starter.bb`). It is a
Go network-provisioning service ([gitlab.com/pantacor/pvwificonnect](https://gitlab.com/pantacor/pvwificonnect))
that lets a headless device be joined to a WiFi network without a console.

It offers **two provisioning transports at the same time**, and you can use
whichever is convenient for the device in front of you:

| Transport | How you reach the device | Typical client |
|-----------|--------------------------|----------------|
| **WiFi access point** | The device broadcasts a setup SSID (default `pvwificonnect` / `1234567890`); you join it and use the web page it serves. | Phone/laptop browser |
| **Bluetooth LE (Improv WiFi)** | The device advertises the [Improv WiFi](https://www.improv-wifi.com/ble/) BLE service; you send SSID + password over BLE without joining any WiFi network. | [hub.pantacor.com/provision-wifi](https://hub.pantacor.com/provision-wifi) or `pvr wifi` |

BLE provisioning is enabled by default and starts automatically when a
Bluetooth adapter is present — nothing extra to configure. Both transports
drive the same backend, so a device can be provisioned either way.

## What it brings to the system

| Feature | Description |
|---------|-------------|
| **Access point** | Broadcasts a setup SSID (default `pvwificonnect` / `1234567890`) so a phone/laptop can connect to the device. |
| **Captive portal** | Redirects connecting clients to a web setup page (opt-in via `captive_portal`). |
| **Improv WiFi over BLE** | Advertises the Improv GATT service so a browser or CLI can scan, provision, identify, rename, and read claim material over Bluetooth (`ble`, on by default). |
| **Internet tethering** | Shares the device's uplink (`eth0`, `wwan0`, …) to AP clients (opt-in via `tethering`). |
| **Auto mode** | Picks portal vs. tethering automatically based on connectivity (`auto_mode`, on by default). |
| **Connection watcher** | Background loop that re-triggers AP/tethering setup when connectivity is lost (`watcher`). |
| **Pre-seeded network** | A `network` block in `config.json` joins a known WiFi network on first boot with no interaction. |
| **Pluggable backend** | Talks to the network stack over D-Bus (`org.pantacor.PvWificonnect`); adapts to whichever backend container is present. |

It is built three ways in this layer:

| Recipe | Produces |
|--------|----------|
| `recipes-containers/pantavisor/pvwificonnect_v1.8.2.bb` | The pvrexport container (this doc). |
| `recipes-containers/pantavisor/pvwificonnect-app_v1.8.2.bb` | The `pvwificonnect` binary built from source. |
| `recipes-containers/pantavisor/pv-pvwificonnect_v1.8.2.bb` | The prebuilt Docker-image variant. |

## Network backend dependency

`pvwificonnect` does not manage WiFi or Bluetooth hardware itself — it drives a
backend over the **host D-Bus** (imported via `os:/pvrun/dbus:/var/run/dbus`,
see `args.json`). The starter image pairs it with the ConnMan backend:

```bitbake
PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi pv-avahi-browse"
```

| Backend container | Stack | AP gateway IP |
|-------------------|-------|---------------|
| `pv-alpine-connman` (default here) | ConnMan tethering API + dnsmasq | `192.168.0.1` |
| Debian / NetworkManager | NM "shared" connection profiles | `10.42.0.1` |

`pv-alpine-connman` also runs **BlueZ** (`bluetoothd`, plus an rfkill
soft-unblock at boot) and exports the system bus through `xdg-dbus-proxy` at
`/pvrun/dbus`, which is how `pvwificonnect` reaches `org.bluez` for BLE
provisioning. It declares `wifi`, `usbnet` and `bluetooth` in
`PV_DRIVERS_OPTIONAL`, so Pantavisor loads the matching driver groups when the
board provides them.

If neither backend is running, the service waits at startup up to
`wait_time_in_sec` for D-Bus readiness. The board must also have working WiFi
firmware and a `wlanN` interface — see the board flashing guides
(e.g. [Verdin iMX8MM](../../getting-started/how-to-install/boards/verdin-imx8mm.md),
[Colibri iMX6ULL](../../getting-started/how-to-install/boards/colibri-imx6ull.md)) for enabling the
WiFi DTB and firmware. BLE additionally needs Bluetooth firmware and an `hciN`
adapter; when no adapter is found, the BLE server logs why and the rest of the
service keeps running.

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
| `ble.enabled` | Improv BLE provisioning server | `true` (skipped when no adapter) |
| `ble.adapter_id` | BlueZ adapter to use | `hci0` (falls back to the first adapter found) |
| `ble.device_name` | Name advertised over BLE | the AP SSID |

> Change the default AP SSID/password before shipping a product image — the
> `1234567890` default is for bring-up only. Set `ble.device_name` too, so
> technicians can tell devices apart in the Bluetooth device list.

Example with BLE named and the captive portal on:

```json
{
    "ap": {
        "ssid": "acme-gateway",
        "password": "a-real-password"
    },
    "ble": {
        "device_name": "acme-gateway-kitchen"
    },
    "captive_portal": true,
    "watcher": true
}
```

### Environment variables

Environment overrides `config.json`. The container's Docker config
(`recipes-containers/pantavisor/pvwificonnect/config.json`) sets the first two;
the rest are unset unless you add them:

| Variable | Meaning | Shipped value | App default |
|----------|---------|---------------|-------------|
| `PV_WIFI_CONNECT_WATCHER` | Enable the connection watcher | `true` | `false` |
| `PV_WIFI_CONNECT_INTERVAL` | Watcher interval (Go duration) | `1m` | `1m` |
| `PV_WIFI_CONNECT_MAX_RETRIES` | Max consecutive watcher failures | *(unset)* | `3` |
| `PV_WIFI_CONNECT_BLE` | Enable/disable BLE provisioning (`0` or `false` disables); takes precedence over `ble.enabled` | *(unset)* | enabled |

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

The recipe additionally attaches `--volume ovl:/tmp:permanent`, so the `/tmp`
volume the container declares survives revision changes.

## Provisioning over Bluetooth (Improv WiFi)

This is the recommended path for a device that has never been on a network: you
do not have to leave your own WiFi, and Pantacor Hub can hand you straight into
claiming the device afterwards.

The device implements the [Improv WiFi BLE spec](https://www.improv-wifi.com/ble/)
— capabilities byte, `0x01` Send WiFi, `0x02` Identify, `0x03` Device Info,
`0x04` Scan, `0x05` Hostname, `0x06` Device Name — plus a Pantacor extension,
`0x07` Pantavisor Claim, advertised as the `pantavisor-claim` capability. That
extra RPC returns the device ID and claim challenge, which is what lets a
client continue into claiming without a serial console.

### From Pantacor Hub (browser)

1. Open [hub.pantacor.com/provision-wifi](https://hub.pantacor.com/provision-wifi)
   in a Web Bluetooth-capable browser (Chrome, Edge or another Chromium-based
   browser; Firefox and Safari do not implement Web Bluetooth).
2. Pair with your device from the browser's Bluetooth chooser — it appears
   under `ble.device_name` (the AP SSID by default).
3. The page asks the device to scan and lists the WiFi networks it sees, with
   signal strength. Pick one and enter the password.
4. The device joins the network. If it advertises `pantavisor-claim`, the page
   waits for it to come online, reads its device ID and claim challenge over
   BLE, and offers to claim it with those values prefilled.

Provisioning itself does not require a Hub login; claiming does.

### From the command line

The Improv BLE client is built into [pvr](https://gitlab.com/pantacor/pvr) as
`pvr wifi` — one tool for both provisioning and everything else you do with a
device:

```bash
pvr wifi device-scan                                   # find Improv devices
pvr wifi provision AA:BB:CC:DD:EE:FF --ssid MyNetwork  # prompts for password
pvr wifi claim-info AA:BB:CC:DD:EE:FF                  # device-id + challenge
```

Other subcommands: `identify` (blink/beep), `device-info` (firmware, hardware,
device name), `hostname` (get or set), `wifi-scan` (networks the device sees).

`pvr wifi` is available on Linux builds only, and needs BlueZ running
(`bluetoothd`) plus adapter access — usually membership in the `bluetooth`
group, or root. Addresses are MACs (`AA:BB:CC:DD:EE:FF`), as printed by
`pvr wifi device-scan`.

Claim material only exists after the device's first rendezvous with Pantacor
Hub, so `claim-info` retries (default: every 5s for up to 60s) until it shows up.

## Provisioning over the setup hotspot

This is the path that needs nothing but a phone: the device puts up its own
WiFi hotspot, you join it, and a web page on the device asks which network to
join.

### When the hotspot comes up

On every start, `pvwificonnect` walks the same ladder:

1. **Already connected to WiFi?** Then no hotspot is started at all.
2. **`network.ssid` set in `config.json`?** It joins that network first. This
   is re-applied on every start, so boards with a randomised station MAC
   recover after a reboot. A failure here (out of range, wrong passphrase)
   falls through to the next step rather than leaving the device stranded.
3. **Otherwise the hotspot goes up** with `ap.ssid` / `ap.password` (default
   `pvwificonnect` / `1234567890`).

With `watcher` enabled, this runs again whenever the link drops, so a device
that loses its network puts its hotspot back up by itself — which is also what
the "the AP will be back up in a few minutes" line on the portal's success page
refers to.

### Captive portal or tethering

What the hotspot does for its clients depends on the mode:

| `auto_mode` | Decision |
|-------------|----------|
| `true` (default) | The service probes the uplink (`uplink_interface`, else `eth0`/`eth1`/…) for an address and real internet reachability. **Uplink with internet → tethering**; **no uplink → captive portal**. |
| `false` | Whatever `captive_portal` and `tethering` say explicitly. |

In **captive portal** mode the service asks the backend over D-Bus
(`ActivateCaptivePortal`) to point dnsmasq's DNS at the device and install the
iptables rules that redirect client traffic to it — that is what makes phones
pop up their "Sign in to network" sheet on joining. In **tethering** mode the
backend installs NAT rules instead and AP clients reach the internet through
the device's uplink.

### Walkthrough

1. **Boot a device** running the starter image with both `pvwificonnect` and a
   network backend (`pv-alpine-connman`). The service starts in the `platform`
   group.
2. **Join the hotspot** from a phone or laptop: SSID `ap.ssid`, password
   `ap.password`. The backend's DHCP hands you an address on its subnet —
   `192.168.0.x` with ConnMan (gateway `192.168.0.1`), `10.42.0.x` with
   NetworkManager (gateway `10.42.0.1`).
3. **Open the portal.** With the captive portal active, the sign-in sheet opens
   by itself; otherwise browse to the gateway address, e.g.
   `http://192.168.0.1`. Every path redirects to `/connect`. The service
   listens on ports 80 and 443, both plain HTTP — a captive-portal probe that
   arrives on 443 still gets the page.
4. **Pick a network.** The page lists the WiFi networks the device can see with
   signal strength and frequency, and has a rescan button. Select one, type the
   password (there is a "Show Password" toggle), and submit.
5. **The device switches over.** It saves the credentials, joins the network
   and **stops the hotspot** — so your phone drops off and the portal becomes
   unreachable; that is the expected outcome, not a failure. The page you were
   left on says "Applying changes…". If the join fails, the hotspot returns
   within a few minutes and you can retry.
6. **Confirm.** Once the device is on your LAN, reopening the page (now on its
   LAN address) shows "Congratulations!" with the `wlan0` address, gateway and
   DNS.

Pre-seeding `network.ssid` / `network.password` in `config.json` skips all of
this: the device joins that network on boot with no interaction.

### Portal HTTP API

The portal is the same HTTP service a script can drive — send
`Accept: application/json` and every endpoint answers JSON instead of HTML:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` , `/captive-portal` | GET | Redirect to `/connect` |
| `/connect` | GET | The setup page: visible networks, and the current connection when there is one |
| `/connections` | GET | Rescan and list visible networks |
| `/connections` | POST | Submit credentials — form fields, or JSON `{"ssid": "...", "password": "...", "frequency": 0}` |
| `/success` | GET | The "applying changes" page |
| `/healthz` | GET | Liveness check |

```bash
curl -H 'Accept: application/json' http://192.168.0.1/connections
curl -X POST -H 'Content-Type: application/json' \
     -d '{"ssid":"MyNetwork","password":"MyPassword"}' \
     http://192.168.0.1/connections
```

Both `ssid` and `password` are required — the portal rejects an empty password
with `400`, so open networks cannot be joined this way. When the hotspot is up, the POST returns immediately and the join
happens in the background, because answering after the AP has been torn down
would never reach the client.

## Building

```bash
./kas-container build kas/build-configs/release/container-x86_64-scarthgap.yaml \
    --target pvwificonnect
```

Output: `build/tmp-scarthgap/deploy/images/<machine>/pvwificonnect.pvrexport.tgz`.
Because it is in `PVROOT_CONTAINERS_CORE`, a full `pantavisor-starter` build
already includes it.

## Related

- [pvr wifi commands](../../../pvr/commands/wifi.md) — the Improv BLE client shipped with pvr
- [Container Development](../container-development.md) — authoring and packaging containers
- [pvwificonnect upstream](https://gitlab.com/pantacor/pvwificonnect) — service source and backend details
- [Improv WiFi](https://www.improv-wifi.com/) — the provisioning protocol spec
