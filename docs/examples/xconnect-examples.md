# xconnect Example Containers

The `pv-examples` containers in `recipes-containers/pv-examples/` demonstrate pv-xconnect service mesh patterns. For the underlying xconnect concepts and manifest format, see the [pantavisor xconnect overview](../../pantavisor/docs/overview/xconnect.md) and [reference](../../pantavisor/docs/reference/pantavisor-xconnect.md).

## Overview

| Pattern | Provider | Consumer(s) | Description |
|---------|----------|-------------|-------------|
| Unix Socket | `pv-example-unix-server` | `pv-example-unix-client` | Raw Unix domain socket proxy |
| REST | `pv-example-rest-server` | `pv-example-rest-client` | HTTP-over-UDS with identity injection |
| D-Bus | `pv-example-dbus-server` | `pv-example-dbus-client` | Policy-aware D-Bus proxy |
| DRM | `pv-example-drm-provider` | `pv-example-drm-master`, `pv-example-drm-render` | Device node injection |
| Wayland | `pv-example-wayland-server` | `pv-example-wayland-client` | Wayland compositor access |

Auto-recovery containers:

| Container | Group | Description |
|-----------|-------|-------------|
| `pv-example-recovery` | root | Crashes after 10s, `on-failure` with `backoff_policy="10min"` |
| `pv-example-stabilize` | root | Fails 3× then stabilizes, `backoff_policy="reboot"` |
| `pv-example-random` | root | Random exit timing, `always` policy |
| `pv-example-app-crash` | app | Inherits app group's auto_recovery |

## Building Example Containers

```bash
# Build specific containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client

# Build with workspace (when iterating on pantavisor source)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-unix-server --target pv-example-unix-client
```

Output: `build/tmp-scarthgap/deploy/images/docker-x86_64/<name>.pvrexport.tgz`

## Quick Test Setup

```bash
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/

docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
docker exec pva-test lxc-ls -f
docker exec pva-test pvcontrol graph ls
```

---

## Unix Socket Example

Demonstrates raw Unix domain socket proxying between containers.

**Provider** `pv-example-unix-server` — creates `/run/example/raw.sock`
**Consumer** `pv-example-unix-client` — expects socket at `/run/pv/services/raw.sock`

### Configuration

**Provider `services.json`:**
```json
[
  {"name": "raw", "type": "unix", "socket": "/run/example/raw.sock"}
]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "raw", "target": "/run/pv/services/raw.sock"}
  ]
}
```

### Build and Verify

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-*.pvrexport.tgz pvtx.d/
```

After containers start:
```bash
docker exec pva-test pvcontrol graph ls   # shows unix link
CLIENT_PID=$(docker exec pva-test lxc-info -n pv-example-unix-client -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$CLIENT_PID/root/run/pv/services/   # injected socket
```

---

## REST Example

Demonstrates HTTP-over-UDS with identity header injection (`X-PV-Client`, `X-PV-Role`).

**Provider `services.json`:**
```json
[
  {"name": "api", "type": "rest", "socket": "/run/example/api.sock"}
]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "api", "target": "/run/pv/services/api.sock"}
  ]
}
```

### Build

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-rest-server --target pv-example-rest-client
```

---

## D-Bus Example

Demonstrates policy-aware D-Bus proxying with role-to-UID mapping.

**Provider** runs a local `dbus-daemon` and Python service, publishing `org.pantavisor.Example`.

**Provider D-Bus policy (`org.pantavisor.Example.conf`):**
```xml
<busconfig>
  <policy user="root">
    <allow own="org.pantavisor.Example"/>
    <allow send_destination="org.pantavisor.Example"/>
  </policy>
  <policy context="default">
    <allow send_destination="org.pantavisor.Example"/>
  </policy>
</busconfig>
```

**Provider `services.json`:**
```json
[{"name": "system-bus", "type": "dbus", "socket": "/run/dbus/system_bus_socket"}]
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {
      "name": "system-bus",
      "type": "dbus",
      "interface": "org.pantavisor.Example",
      "target": "/run/dbus/system_bus_socket"
    }
  ]
}
```

### Build and Verify

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-dbus-server --target pv-example-dbus-client
```

Check client logs for successful D-Bus call:
```bash
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log
# Expected: method return with org.pantavisor.Example response
```

---

## DRM Example

Demonstrates DRM device node injection for graphics access.

**Provider** `pv-example-drm-provider` — exports DRM devices
**Consumer** `pv-example-drm-master` — requests `/dev/dri/card0` (KMS)
**Consumer** `pv-example-drm-render` — requests `/dev/dri/renderD128` (GPU rendering)

**Provider `services.json`:**
```json
[
  {"name": "drm-master", "type": "drm", "socket": "/dev/dri/card0"},
  {"name": "drm-render", "type": "drm", "socket": "/dev/dri/renderD128"}
]
```

**Consumer `args.json` (drm-master):**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "drm-master", "target": "/dev/dri/card0"}]
}
```

### Testing with VKMS

```bash
sudo modprobe vkms
ls -la /dev/dri/   # card0 (VKMS does not create renderD* nodes)
```

| Device | VKMS | Use case |
|--------|------|----------|
| `/dev/dri/card0` | Yes | KMS/display |
| `/dev/dri/renderD128` | No | GPU compute |

### Build and Run

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider --target pv-example-drm-master
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-*.pvrexport.tgz pvtx.d/

# Run with DRM device passthrough
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
```

Verify injection:
```bash
MASTER_PID=$(docker exec pva-test lxc-info -n pv-example-drm-master -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$MASTER_PID/root/dev/dri/   # expect card0 226:0
```

---

## Wayland Example

Demonstrates Wayland compositor access. Requires DRM.

**Provider** `pv-example-wayland-server` — Weston compositor (requires DRM from drm-provider)
**Consumer** `pv-example-wayland-client` — Wayland client

**Provider `services.json`:**
```json
[{"name": "wayland-0", "type": "wayland", "socket": "/run/wayland/wayland-0"}]
```

**Provider `args.json` (requires DRM):**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "drm-master", "target": "/dev/dri/card0"}]
}
```

**Consumer `args.json`:**
```json
{
  "PV_SERVICES_REQUIRED": [{"name": "wayland-0", "target": "/run/wayland/wayland-0"}]
}
```

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider \
    --target pv-example-wayland-server \
    --target pv-example-wayland-client
```

> VKMS provides `card0` but won't produce actual display output. Full Wayland testing requires real GPU hardware.

---

## Debugging Tips

```bash
# Container status
docker exec pva-test lxc-ls -f

# Enter a container
docker exec -it pva-test pventer -c <container_name>

# Container namespace inspection
docker exec pva-test lxc-info -n <container_name> -p
docker exec pva-test ls -la /proc/<PID>/root/run/

# Common issues
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately | Missing DRM device | Add `--device /dev/dri:/dev/dri` |
| Socket not injected | pv-xconnect not running | `docker exec pva-test pvcontrol daemons ls` |
| "Connection refused" | Provider not ready | Wait for provider container RUNNING status |
| Device not found | Wrong major:minor | `stat /dev/dri/card0` on host |

```bash
# Cleanup between tests
docker rm -f pva-test
docker volume rm storage-test
```
