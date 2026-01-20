# Pantavisor Example Containers

This document describes the example containers provided in `meta-pantavisor` for testing and demonstrating pv-xconnect service mesh functionality.

## Overview

The `pv-examples` containers demonstrate various service mesh patterns supported by pv-xconnect:

| Pattern | Provider | Consumer(s) | Description |
|---------|----------|-------------|-------------|
| Unix Socket | `pv-example-unix-server` | `pv-example-unix-client` | Raw Unix domain socket proxy |
| REST | `pv-example-rest-server` | `pv-example-rest-client` | HTTP-over-UDS with identity injection |
| D-Bus | `pv-example-dbus-server` | `pv-example-dbus-client` | Policy-aware D-Bus proxy |
| DRM | `pv-example-drm-provider` | `pv-example-drm-master`, `pv-example-drm-render` | Device node injection |
| Wayland | `pv-example-wayland-server` | `pv-example-wayland-client` | Wayland compositor access |

## Building Example Containers

Build example containers using kas-container:

```bash
cd /path/to/meta-pantavisor

# Build specific containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client

# Build with workspace (when iterating on pantavisor source)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-unix-server --target pv-example-unix-client
```

The pvrexport outputs are in:
```
build/tmp-scarthgap/deploy/images/docker-x86_64/<container-name>.pvrexport.tgz
```

## Testing with Appengine

See [DEVELOPMENT.md](DEVELOPMENT.md) for the complete appengine workflow.

### Quick Test Setup

```bash
# Prepare pvrexport directory
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/

# Start appengine
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

# Start pv-appengine and wait for READY
docker exec pva-test sh -c 'pv-appengine &'
sleep 10
docker exec pva-test grep "status is now READY" /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log

# Verify containers are running
docker exec pva-test lxc-ls -f

# Check xconnect-graph
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
```

---

## Unix Socket Example

Demonstrates raw Unix domain socket proxying between containers.

### Containers

- **Provider**: `pv-example-unix-server` - Creates `/run/example/raw.sock`
- **Consumer**: `pv-example-unix-client` - Expects socket at `/run/pv/services/raw.sock`

### Configuration

**Provider services.json:**
```json
[
  {"name": "raw", "type": "unix", "socket": "/run/example/raw.sock"}
]
```

**Consumer args.json:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "raw", "target": "/run/pv/services/raw.sock"}
  ]
}
```

### Build and Test

```bash
# Build containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server --target pv-example-unix-client

# Copy to pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-*.pvrexport.tgz pvtx.d/
```

### Verify

After containers start:
```bash
# Check xconnect graph shows the link
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph

# Get consumer PID and check injected socket
docker exec pva-test lxc-info -n pv-example-unix-client -p
docker exec pva-test ls -la /proc/<PID>/root/run/pv/services/
```

---

## REST Example

Demonstrates HTTP-over-UDS with identity header injection (`X-PV-Client`, `X-PV-Role`).

### Containers

- **Provider**: `pv-example-rest-server` - HTTP server on `/run/example/api.sock`
- **Consumer**: `pv-example-rest-client` - Expects API at `/run/pv/services/api.sock`

### Configuration

**Provider services.json:**
```json
[
  {"name": "api", "type": "rest", "socket": "/run/example/api.sock"}
]
```

**Consumer args.json:**
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

Demonstrates policy-aware D-Bus proxying with interface filtering and name ownership.

### Containers

- **Provider**: `pv-example-dbus-server`
  - Runs a local `dbus-daemon` and a Python service.
  - Publishes the `org.pantavisor.Example` bus name.
  - Includes a policy file in `/etc/dbus-1/system.d/` to grant permissions.
- **Consumer**: `pv-example-dbus-client`
  - Calls `GetInfo` on the `org.pantavisor.Example` service using `dbus-send`.
  - Expects the proxied bus socket to be injected at `/run/dbus/system_bus_socket`.

### Configuration

**Provider services.json:**
```json
[
  {
    "name": "system-bus",
    "type": "dbus",
    "socket": "/run/dbus/system_bus_socket"
  }
]
```

**Consumer args.json:**
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

- **`interface`**: Defines the D-Bus name or interface the consumer is allowed to access.
- **`target`**: The path inside the consumer namespace where `pv-xconnect` will inject the proxied D-Bus socket.

### Build and Test

```bash
# Build D-Bus containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-dbus-server --target pv-example-dbus-client

# Copy to pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-dbus-*.pvrexport.tgz pvtx.d/
```

### Verify

After containers start and `pv-xconnect` reconciles the graph:
```bash
# Observe client logs for successful D-Bus replies
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log
```

Expected output:
```
--- Requesting info from D-Bus service org.pantavisor.Example ---
method return time=... sender=:1.0 -> destination=:1.1 serial=... reply_serial=2
   string "{"service": "dbus-example", "status": "active"}"
```

---

## DRM Example

Demonstrates DRM device node injection for graphics access.

### Containers

- **Provider**: `pv-example-drm-provider` - Exports DRM devices
- **Consumer (Master)**: `pv-example-drm-master` - Requests `/dev/dri/card0` (KMS access)
- **Consumer (Render)**: `pv-example-drm-render` - Requests `/dev/dri/renderD128` (GPU rendering)

### Configuration

**Provider services.json:**
```json
[
  {"name": "drm-master", "type": "drm", "socket": "/dev/dri/card0"},
  {"name": "drm-render", "type": "drm", "socket": "/dev/dri/renderD128"}
]
```

**Consumer args.json (drm-master):**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "drm-master", "target": "/dev/dri/card0"}
  ]
}
```

### Testing with VKMS

VKMS (Virtual Kernel Mode Setting) allows testing DRM injection without real GPU hardware.

```bash
# Load VKMS on host
sudo modprobe vkms
ls -la /dev/dri/
# Expected: card0 (VKMS doesn't create renderD* nodes)
```

**VKMS Limitations:**

| Device Type | VKMS Support | Use Case |
|-------------|--------------|----------|
| `/dev/dri/card0` | Yes | KMS/display access |
| `/dev/dri/renderD128` | No | GPU compute/rendering |

### Build and Test

```bash
# Build DRM containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider --target pv-example-drm-master

# Copy to pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-*.pvrexport.tgz pvtx.d/

# Run appengine with DRM device passthrough
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
```

### Verify DRM Injection

```bash
# Start pv-appengine
docker exec pva-test sh -c 'pv-appengine &'
sleep 10

# pv-xconnect runs as daemon and injects devices automatically
# Check consumer namespace for injected device
docker exec pva-test lxc-info -n pv-example-drm-master -p
docker exec pva-test ls -la /proc/<PID>/root/dev/dri/
```

Expected: `/dev/dri/card0` with major:minor `226:0`

### Hardware Testing

For full DRM testing including render nodes:

- **Raspberry Pi 4/5**: VC4/V3D driver (card0 + renderD128)
- **x86 with Intel GPU**: i915 driver
- **x86 with AMD GPU**: amdgpu driver
- **ARM SoC boards**: Mali, Adreno drivers

---

## Wayland Example

Demonstrates Wayland compositor access with DRM dependency.

### Containers

- **Provider**: `pv-example-wayland-server` - Weston compositor (requires DRM)
- **Consumer**: `pv-example-wayland-client` - Wayland client application

### Configuration

**Provider services.json:**
```json
[
  {"name": "wayland-0", "type": "wayland", "socket": "/run/wayland/wayland-0"}
]
```

**Provider args.json (requires DRM):**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "drm-master", "target": "/dev/dri/card0"}
  ]
}
```

**Consumer args.json:**
```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "wayland-0", "target": "/run/wayland/wayland-0"}
  ]
}
```

### Build

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider \
    --target pv-example-wayland-server \
    --target pv-example-wayland-client
```

### Notes

- Wayland server requires DRM access for display output
- Full Wayland testing requires real GPU hardware or a display server
- VKMS can provide card0 but won't produce actual display output

---

## Debugging Tips

### Check Container Status
```bash
docker exec pva-test lxc-ls -f
```

### Enter a Container
```bash
docker exec -it pva-test pventer -c <container_name>
```

### Check Container's Namespace
```bash
# Get container PID
docker exec pva-test lxc-info -n <container_name> -p

# List files in container's rootfs
docker exec pva-test ls -la /proc/<PID>/root/run/
```

### Log Locations

| Log | Path |
|-----|------|
| Pantavisor | `/run/pantavisor/pv/logs/0/pantavisor/pantavisor.log` |
| Container Console | `/run/pantavisor/pv/logs/0/<container>/lxc/console.log` |
| LXC Log | `/run/pantavisor/pv/logs/0/<container>/lxc/lxc.log` |

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container exits immediately | Missing DRM device | Add `--device /dev/dri:/dev/dri` |
| Socket not injected | pv-xconnect not running | Check `ps aux \| grep pv-xconnect` |
| "Connection refused" | Provider not ready | Wait for provider container to start |
| Device not found | Wrong major:minor | Check `stat /dev/dri/card0` on host |

### Cleanup Between Tests

```bash
docker rm -f pva-test
docker volume rm storage-test
```
