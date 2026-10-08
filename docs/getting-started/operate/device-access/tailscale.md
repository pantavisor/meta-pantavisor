---
title: Tailscale VPN
sidebar_position: 8
description: Reach a Pantavisor device over a Tailscale mesh VPN with the pv-tailscale container, enabled and configured through user metadata.
---

The `pv-tailscale` container joins the device to a [Tailscale](https://tailscale.com)
tailnet, so you can reach it (SSH, the pvtx web UI on port 12368, and any
container on the host network) from anywhere, with no port forwarding. Once it
is installed, you turn it on and configure it entirely through
[user metadata](../../develop/cli-tools/pvcontrol.md#metadata), either from the
device or from Pantahub.

:::note
The container ships **disabled**. Until the user-meta key `tailscale.enabled`
is `true`, the Tailscale daemon does not start. `tailscale` commands inside
the container then fail with
`dial unix /var/run/tailscale/tailscaled.sock: connect: no such file or directory`.
:::

## Add it to an image

`pv-tailscale` is a recipe in this layer
(`recipes-containers/pantavisor/pv-tailscale_<version>.bb`). It packages a prebuilt
pvrexport of `registry.gitlab.com/highercomve/ph-tailscale`. Add it to the
image's containers, and enable the `tailscale` feature so the kernel gets the
TUN, WireGuard, and netfilter options it needs:

```bitbake
PVROOT_CONTAINERS_CORE:append = " pv-tailscale"
PANTAVISOR_FEATURES:append = " tailscale"
```

The kernel fragment depends on the firewall backend.
`recipes-kernel/linux/files/tailscale-nftables.cfg` is used when `nftables` is
in `IMAGE_INSTALL`; otherwise the image gets `tailscale-iptables.cfg`.

## Enable and configure

The container reads two user-meta keys, mounted inside it under
`/pantavisor/user-meta/`:

| Key | Value | Effect |
|-----|-------|--------|
| `tailscale.enabled` | `true` | Starts `tailscaled` and brings the connection up. Any other value or no key: the client runs `tailscale down` |
| `tailscale.config` | JSON object (below) | Options for `tailscale up`. Without this key, the container uses `/etc/tailscale/config.json`, which only has placeholders |

From a shell on the device:

```bash
pvcontrol usrmeta save tailscale.config '{"key":"tskey-auth-XXXXXXXX","ssh":false,"acceptroutes":true,"acceptdns":true}'
pvcontrol usrmeta save tailscale.enabled true
```

You can also set the same keys in the device's user metadata on
[Pantahub](https://hub.pantacor.com). This works for devices you can't reach
locally yet.

### `tailscale.config` keys

Each key maps to a `tailscale up` flag. Keys you leave out are not passed.

| Key | Type | `tailscale up` flag |
|-----|------|---------------------|
| `key` | string | `--authkey`. Only used while the node has no valid credentials (`NeedsLogin`/`NoState`) |
| `hostname` | string | `--hostname`. Ignored when `/pantavisor/device-id` is set; the Pantahub device ID is used instead |
| `ssh` | bool | `--ssh` |
| `acceptdns` | bool | `--accept-dns` |
| `acceptroutes` | bool | `--accept-routes` |
| `advertiseroutes` | string | `--advertise-routes` |
| `advertisetags` | string | `--advertise-tags` |
| `hostroutes` | bool | `--host-routes` |
| `loginserver` | string | `--login-server` (e.g. a Headscale server) |
| `netfiltermode` | string | `--netfilter-mode` |
| `shieldsup` | bool | `--shields-up` |
| `snatsubnetroutes` | bool | `--snat-subnet-routes` |

Every connection attempt also passes `--reset`, so settings not in the config
fall back to Tailscale's defaults.

If you leave `key` out, the client logs `Node needs authentication but no auth
key configured` and waits. You can log in by hand instead from the container
(below).

## Check the connection

Open a shell in the container. On the serial console or the host SSH shell,
run:

```bash
pventer -c tailscale
```

Then:

```bash
ls /pantavisor/user-meta/     # tailscale.enabled (and tailscale.config) listed
pgrep tailscaled              # daemon running once tailscale.enabled is true
tailscale status
tailscale login               # interactive login, if no auth key is configured
```

## Disable

```bash
pvcontrol usrmeta save tailscale.enabled false
```

The client runs `tailscale down` within about a second. The daemon itself
keeps running until the container restarts, because it only reads
`tailscale.enabled` at startup.

## Expected boot-log noise

These lines from the container's logs are harmless:

- `rsyslogd: cannot create '/dev/log': Address in use`. Pantavisor mounts its
  own log socket at `/dev/log` in every container, so the image's rsyslog
  can't bind it. Syslog from the container still reaches Pantavisor through
  that socket.
- `pvlogger tailscale ... Cannot init log file`. Pantavisor's default loggers
  watch `/var/log/syslog` and `/var/log/messages`, and these files don't exist
  yet (or never will) in this Alpine image. pvlogger keeps polling for them.
- `Service 'hwdrivers' needs non existent service 'dev'` (same for
  `machine-id`). Neither service is in a runlevel, so neither runs.
