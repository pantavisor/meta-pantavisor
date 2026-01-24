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
### Configuration

**Provider D-Bus Policy (`org.pantavisor.Example.conf`):**
```xml
<busconfig>
  <!-- Allow containers with the 'root' role (mapped to provider's 'root' user) -->
  <policy user="root">
    <allow own="org.pantavisor.Example"/>
    <allow send_destination="org.pantavisor.Example"/>
  </policy>

  <!-- Allow containers with any role that maps to a valid user to SEND messages -->
  <policy context="default">
    <allow send_destination="org.pantavisor.Example"/>
  </policy>
</busconfig>
```
This demonstrates how `pv-xconnect` bridges identities across namespaces by mapping roles defined in the service mesh graph to actual UIDs inside the provider container.

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

## Device Configuration (device.json) Container

Device configuration (IPAM network pools, container groups) is delivered via a signed pvrexport.

### Why a Standalone device.json Container?

- **Embedded Pantavisor**: device.json is typically packaged within the BSP (see `recipes-pv/images/pantavisor-bsp.bb` which signs `device.json` alongside BSP artifacts)
- **Appengine**: There is no BSP directory, so a standalone device.json pvrexport (`pv-example-device-config`) is essential for IPAM and group configuration

The standalone device.json container works for all Pantavisor types and is the recommended approach for appengine testing.

### Creating the device.json Source File

Create `recipes-containers/pv-examples/files/device.json.ipam-example`:

```json
{
    "network": {
        "pools": {
            "internal": {
                "type": "bridge",
                "bridge": "br0",
                "subnet": "10.0.3.0/24",
                "gateway": "10.0.3.1",
                "nat": true
            }
        }
    },
    "groups": [
        {
            "name": "root",
            "description": "Network connectivity containers",
            "restart_policy": "system",
            "status_goal": "STARTED",
            "timeout": 30
        },
        {
            "name": "platform",
            "description": "Middleware and utility containers",
            "restart_policy": "system",
            "status_goal": "STARTED",
            "timeout": 30
        },
        {
            "name": "app",
            "description": "Application level containers",
            "restart_policy": "container",
            "status_goal": "STARTED",
            "timeout": 30
        }
    ]
}
```

### Recipe Structure

Create `recipes-containers/pv-examples/pv-example-device-config_1.0.bb`:

```bitbake
SUMMARY = "Device configuration with IPAM network pools"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "pvr-native jq-native"

inherit deploy pvr-ca

# Include pv-developer-ca directly (pvr-ca inheritance doesn't apply SRC_URI)
PVS_URI = "https://gitlab.com/pantacor/pv-developer-ca/-/archive/2340d747c4acd0a1a702b3d7d5acc014b51daaa7/pv-developer-ca-master.tar.gz;striplevel=1"
PVS_URI_SHA256 = "9f4c55dad2c121a4ca2ae39e2767eb4a214822ee34041a65692766ae438f96d8"

SRC_URI = "file://device.json.ipam-example \
           ${PVS_URI};name=pv-developer-ca;subdir=pv-developer-ca_generic \
          "
SRC_URI[pv-developer-ca.sha256sum] = "${PVS_URI_SHA256}"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"
PVR_HOME_DIR = "${WORKDIR}/home"

do_compile[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_compile() {
    export PVR_DISABLE_SELF_UPGRADE=true
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export HOME="${PVR_HOME_DIR}"

    # Extract and set up signing keys
    mkdir -p ${PVR_CONFIG_DIR}
    if [ -d ${WORKDIR}/pv-developer-ca_generic ]; then
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_generic/pvs/pvs.defaultkeys.tar.gz
    fi
    if [ -f "${PVR_CONFIG_DIR}/key.default.pem" ]; then
        export PVR_SIG_KEY="${PVR_CONFIG_DIR}/key.default.pem"
    fi
    if [ -f "${PVR_CONFIG_DIR}/x5c.default.pem" ]; then
        export PVR_X5C_PATH="${PVR_CONFIG_DIR}/x5c.default.pem"
    fi

    cd ${B}/pvrrepo
    pvr init

    # Add device.json (MUST be named device.json in the repo)
    cp -f ${WORKDIR}/device.json.ipam-example device.json

    pvr add
    pvr commit

    # Sign using --raw for non-container files
    pvr sig add -n --raw device-config --include "device.json"
    pvr add
    pvr commit
    pvr sig up
    pvr commit
}

do_deploy[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_deploy() {
    export PVR_DISABLE_SELF_UPGRADE=true
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export HOME="${PVR_HOME_DIR}"

    cd ${B}/pvrrepo
    pvr export ${DEPLOYDIR}/${PN}.pvrexport.tgz
}

addtask deploy after do_compile
```

### Key Points

| Requirement | Details |
|-------------|---------|
| File naming | MUST be `device.json` in pvr repo (not `device.json.example`) |
| Signing command | `pvr sig add --raw <name> --include "device.json"` for non-container files |
| Signing keys | Include pv-developer-ca directly in SRC_URI (pvr-ca class doesn't propagate it) |

### Resulting pvrexport Structure

```json
{
  "#spec": "pantavisor-service-system@1",
  "_sigs/device-config.json": {
    "#spec": "pvs@2",
    "protected": "eyJhbGci...(base64 header)...",
    "signature": "kh2UZSaQ..."
  },
  "device.json": {
    "network": { "pools": { ... } },
    "groups": [ ... ]
  }
}
```

### Build and Deploy

```bash
# Build
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config

# Deploy to pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
```

### Inspect pvrexport

```bash
# Extract and verify structure
mkdir -p /tmp/inspect
tar -xzf pv-example-device-config.pvrexport.tgz -C /tmp/inspect
cat /tmp/inspect/json | jq .

# Decode signature protected header
cat /tmp/inspect/json | jq -r '."_sigs/device-config.json".protected' | base64 -d | jq .
```

---

## IPAM Validation Examples

Demonstrates IPAM (IP Address Management) validation and rollback behavior.

### Containers

- **Valid**: `pv-example-ipam-valid` - Uses valid static IP within subnet (should start)
- **Invalid**: `pv-example-ipam-invalid` - Uses static IP outside subnet (should fail, trigger rollback)
- **Collision**: `pv-example-ipam-collision` - Uses same IP as valid container (should fail when both deployed)

### Prerequisites: device.json with IP Pool

IPAM requires an IP pool defined in `device.json`. For appengine testing, deploy the device-config container:

```bash
# Build and deploy device-config (see Device Configuration section above)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
```

This provides the `internal` pool with subnet `10.0.3.0/24`.

### Container Configuration

**pv-example-ipam-valid (args.json):**
```json
{
    "PV_NETWORK_POOL": "internal",
    "PV_NETWORK_IP": "10.0.3.50",
    "PV_RESTART_POLICY": "container"
}
```

**pv-example-ipam-invalid (args.json):**
```json
{
    "PV_NETWORK_POOL": "internal",
    "PV_NETWORK_IP": "192.168.99.100",
    "PV_RESTART_POLICY": "container"
}
```

The invalid container uses an IP address (192.168.99.100) that is outside the pool's subnet (10.0.3.0/24). This should be detected and rejected.

**pv-example-ipam-collision (args.json):**
```json
{
    "PV_NETWORK_POOL": "internal",
    "PV_NETWORK_IP": "10.0.3.50",
    "PV_RESTART_POLICY": "container"
}
```

Same IP as `pv-example-ipam-valid`, used to test IP collision detection.

### Build and Test

```bash
# Build IPAM test containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-ipam-valid

./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-ipam-invalid

./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-ipam-collision

# Copy to pvtx.d
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-*.pvrexport.tgz pvtx.d/
```

### Test Scenarios

#### Test 1: Valid Static IP (Should Succeed)

```bash
# Copy only the valid container
rm pvtx.d/pv-example-ipam-*.pvrexport.tgz 2>/dev/null
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/

# Setup device.json with IP pool (see Prerequisites above)

# Start appengine
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15

# Check container started successfully
docker exec pva-test lxc-ls -f
# Expected: pv-example-ipam-valid with RUNNING status
```

#### Test 2: Invalid Static IP - Outside Subnet (Should Fail)

```bash
# Copy only the invalid container
rm pvtx.d/pv-example-ipam-*.pvrexport.tgz 2>/dev/null
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-invalid.pvrexport.tgz pvtx.d/

# Reset and start
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15

# Check logs for IPAM validation error
docker exec pva-test cat /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log | grep -i "ipam\|subnet\|refusing"
# Expected: "failed to reserve static IP ... refusing to start"
# Expected: "triggering rollback if in try-boot"

# Container should NOT be running
docker exec pva-test lxc-ls -f
```

#### Test 3: IP Collision (Second Container Should Fail)

```bash
# Copy both valid and collision containers
rm pvtx.d/pv-example-ipam-*.pvrexport.tgz 2>/dev/null
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-collision.pvrexport.tgz pvtx.d/

# Reset and start
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15

# Check logs for collision error
docker exec pva-test cat /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log | grep -i "already in use\|refusing"
# Expected: First container starts, second fails with "already in use"

# Only the first container should be running
docker exec pva-test lxc-ls -f
```

### Expected Behavior

| Scenario | Expected Result | Log Message |
|----------|----------------|-------------|
| Valid static IP | Container starts | `platform 'pv-example-ipam-valid' using static IP 10.0.3.50` |
| IP outside subnet | Container fails, rollback triggered | `failed to reserve static IP ... (already in use or outside subnet), refusing to start` |
| IP collision | Second container fails | `failed to reserve static IP ... (already in use or outside subnet), refusing to start` |

### Rollback Verification

In a real device with try-boot enabled, IPAM failures during system startup will trigger automatic rollback:

1. Update is installed with `pv_try` set to new revision
2. Device reboots into new revision
3. Container with invalid network config fails to start
4. `pv_platform_start()` returns -1, triggering state machine error
5. Pantavisor reboots before committing (`pv_done` unchanged)
6. Bootloader sees `pv_try` still set, returns to previous `pv_done` revision

This ensures network misconfigurations in updates are automatically rolled back.

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
