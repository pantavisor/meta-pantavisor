+++
title = "Access Your Applications"
weight = 44

# SEO Configuration
description = "Access web interfaces of applications running on Pantavisor Linux. Learn about port mapping, remote access, and security considerations."
keywords = ["access pantavisor apps", "web interface", "application ports", "remote access", "app web ui", "device applications", "web application access", "pantavisor web interface", "embedded app access", "container web apps"]
meta_description = "Access Your Applications: Complete guide to accessing web interfaces of applications running on Pantavisor Linux devices via browser."
author = "Pantacor Ltd"

# Open Graph / Social Media
og_title = "Access Applications on Pantavisor Linux"
og_description = "Learn to access web interfaces of applications running on your Pantavisor Linux device. Guide to ports, remote access, and security."
og_type = "article"
og_image = "/images/home-assistant-login.png"

# Twitter specific
twitter_title = "Access Pantavisor Web Applications"
twitter_description = "Access web interfaces of containerized applications running on your embedded Linux device"
twitter_card = "summary_large_image"

# SEO Settings
robots = "index, follow"
sitemap_priority = 0.7
sitemap_changefreq = "monthly"
canonical_url = "https://www.pantavisor.io/learn/device-setup/access-applications/"
+++

Pantavisor containers are isolated LXC namespaces. There are three ways to interact with a running application: enter its namespace directly, reach it over the host network, or wire it to other containers through the pv-xconnect service mesh.

## Enter a Container with pventer

`pventer` drops you into a running container's namespace — the embedded equivalent of `docker exec`:

```bash
pventer -c sensor-app
```

Once inside you have a shell in the container's filesystem, process, and network namespaces. Exit with `exit` or `Ctrl-D` to return to the host.

To inspect the container's filesystem without entering:

```bash
# Get the container's init PID
lxc-info -n sensor-app -p

# Browse the rootfs through /proc
ls -la /proc/<PID>/root/
```

## Reach a Container over the Host Network

If a container binds to a port, it is directly reachable on the device's IP address — no port mapping or NAT is needed. The host and containers share the default network namespace unless the container's `lxc.container.conf` explicitly isolates networking.

Example: a container running an HTTP server on port 8080:

```bash
curl http://<device-ip>:8080/
```

To confirm which port a container is listening on, enter its namespace and inspect:

```bash
pventer -c my-app
ss -tlnp
```

## Container-to-Container Communication with pv-xconnect

When containers need to communicate with each other without sharing a network namespace, use the **pv-xconnect** service mesh. It injects sockets or device nodes directly into a consumer container's namespace.

The provider declares what it exports in `services.json`:

```json
[
  {"name": "api", "type": "rest", "socket": "/run/myapp/api.sock"}
]
```

The consumer declares what it requires in `args.json`:

```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "api", "target": "/run/pv/services/api.sock"}
  ]
}
```

Pantavisor's `pv-xconnect` daemon proxies the connection and injects the socket into the consumer's namespace at `/run/pv/services/api.sock`. No shared network namespace or port exposure is needed.

To inspect the active service mesh:

```bash
pvcontrol graph ls
```

Supported service types:

| Type | Use case |
|------|----------|
| `unix` | Raw Unix domain socket |
| `rest` | HTTP-over-UDS with caller-identity headers |
| `dbus` | Policy-aware D-Bus proxy |
| `drm` | DRM device node injection (`card0`, `renderD128`) |
| `wayland` | Wayland compositor access |

## Remote Access via Tailscale

If the Tailscale container is installed on the device, every container that uses the host network namespace is reachable over the Tailscale mesh network — no router port-forwarding required. Install Tailscale as a regular pvr application:

```bash
pvr app add tailscale --from tailscale/tailscale --platform linux/arm64
pvr add . && pvr commit -m "add Tailscale"
pvr deploy trails/0 .
```

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Container not responding | `pvcontrol container ls` — verify state is RUNNING |
| Port unreachable from host | `pventer -c <app>` then `ss -tlnp` to confirm the port is bound |
| xconnect socket missing | `pvcontrol graph ls` — check link is present; `pvcontrol daemons ls` — confirm pv-xconnect is running |
| Container crashed | `tail /run/pantavisor/pv/logs/0/<app>/lxc/console.log` for the exit reason |