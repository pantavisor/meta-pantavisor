# Development Guide

This guide covers the development workflow for iterating on Pantavisor and containers using the meta-pantavisor layer.

## Prerequisites

- Docker installed and running
- Git configured
- Sufficient disk space (~50GB for builds)

## Repository Setup

Clone meta-pantavisor:
```bash
git clone https://github.com/pantavisor/meta-pantavisor.git
cd meta-pantavisor
```

## Development Modes

### Standard Build (Release)

Build using upstream sources:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml
```

### Workspace Build (Development)

Build with local pantavisor source for development:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
```

This overlays `kas/with-workspace.yaml` which:
- Creates a devtool workspace at `build/workspace/sources/pantavisor`
- Allows direct edits to pantavisor source code
- Rebuilds pantavisor from workspace on each build

**Note on pvr**: When using a custom `pvr` binary from the workspace, auto-updates are disabled by setting `PVR_DISABLE_SELF_UPGRADE=1` in the environment. This is handled automatically by the `container-pvrexport.bbclass`.

## Pantavisor Development

### Initial Setup

First build initializes the workspace:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
```

The workspace sources are at:
```
build/workspace/sources/pantavisor/   # Pantavisor runtime
build/workspace/sources/lxc-pv/       # LXC with pantavisor patches
```

The workspace appends (bbappend files that redirect recipes to use workspace sources):
```
build/workspace/appends/pantavisor_git.bbappend
build/workspace/appends/lxc-pv_git.bbappend
```

### Development Cycle

1. **Edit source code:**
   ```bash
   cd build/workspace/sources/pantavisor
   # Make changes to C files, headers, etc.
   ```

2. **Rebuild:**
   ```bash
   cd /path/to/meta-pantavisor
   ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
   ```

3. **Test with appengine:**
   ```bash
   docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
   # Follow testing workflow below
   ```

4. **Commit when ready:**
   ```bash
   cd build/workspace/sources/pantavisor
   git add -A
   git commit -m "description of changes"
   git push
   ```

### Building Specific Targets

Build only pantavisor (faster iteration):
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pantavisor
```

Build pantavisor and appengine:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pantavisor-appengine
```

## Container Development

### Creating Example Containers

Example containers are in `recipes-containers/pv-examples/`. Each container needs:

1. **Recipe file** (`pv-example-foo_1.0.bb`):
   ```bitbake
   SUMMARY = "Example Foo Container"
   LICENSE = "MIT"
   LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

   inherit core-image container-pvrexport

   IMAGE_BASENAME = "pv-example-foo"
   PVRIMAGE_AUTO_MDEV = "0"

   IMAGE_INSTALL += "busybox"

   SRC_URI += "file://${PN}.services.json \
               file://${PN}.args.json"

   PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/bin/sh"
   ```

2. **services.json** (for providers):
   ```json
   {
     "#spec": "service-manifest-xconnect@1",
     "services": [
       {"name": "my-service", "type": "unix", "socket": "/run/my-service.sock"}
     ]
   }
   ```

   > **Note**: The `#spec` versioning format is required. The parser supports both the new object format and legacy array format for backwards compatibility.

3. **args.json** (for consumers):
   ```json
   {
     "PV_SERVICES_REQUIRED": [
       {"name": "my-service", "target": "/run/pv/services/my-service.sock"}
     ]
   }
   ```

### Building Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-foo
```

Output: `build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-foo.pvrexport.tgz`

### Inspecting Pvrexports

Always use `pvr` tools to inspect pvrexports, not manual tar extraction:

```bash
# Quick inspection - show state JSON
pvr inspect /path/to/container.pvrexport.tgz

# Clone to directory for detailed inspection
pvr clone /path/to/container.pvrexport.tgz /tmp/inspect-dir
ls /tmp/inspect-dir/
cat /tmp/inspect-dir/<container-name>/run.json
```

The `pvr inspect` command outputs the full state JSON including all container configurations (run.json, services.json, etc.) embedded in the state

## Appengine Testing Workflow

### Load Docker Image

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Prepare Test Containers

```bash
mkdir -p pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-*.pvrexport.tgz pvtx.d/
```

### Start Appengine (Interactive Mode)

For development, use interactive mode with manual control:

```bash
# Clean previous state
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null

# Start container with sleep (keeps it alive for manual control)
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

# Start pv-appengine manually
docker exec pva-test sh -c 'pv-appengine &'
```

### Start Appengine (Auto Mode)

For simple testing, use auto mode:

```bash
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    pantavisor-appengine:1.0
```

### Verify Startup

```bash
# Wait for READY status
sleep 10
docker exec pva-test grep "status is now READY" /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log

# Check containers are running
docker exec pva-test lxc-ls -f
```

### Device Passthrough

For DRM/graphics testing:
```bash
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
```

## Debugging

### Pantavisor Logs

```bash
# Appengine log path
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log

# Tail logs in real-time
docker exec pva-test tail -f /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
```

### Container Logs

```bash
docker exec pva-test cat /var/pantavisor/storage/logs/0/<container_name>/lxc/console.log
```

> **Note**: In appengine, logs are at `/var/pantavisor/storage/logs/0/` rather than `/run/pantavisor/pv/logs/0/`.

### Enter Container Namespace

```bash
docker exec -it pva-test pventer -c <container_name>
```

### Check Container Filesystem

```bash
# Get container PID
docker exec pva-test lxc-info -n <container_name> -p

# Access container rootfs
docker exec pva-test ls -la /proc/<PID>/root/
```

### API Testing

Pantavisor includes `pvcurl`, a lightweight wrapper around `nc` for communicating with the `pv-ctrl` socket.

```bash
# xconnect graph
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .

# Daemon management
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons | jq .
docker exec pva-test pvcurl -X PUT --data '{"action":"stop"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect

# Container status
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers | jq .

# Container lifecycle control (requires restart_policy: "container")
docker exec pva-test pvcurl -X PUT --data '{"action":"stop"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/<container_name>
docker exec pva-test pvcurl -X PUT --data '{"action":"start"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/<container_name>
docker exec pva-test pvcurl -X PUT --data '{"action":"restart"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/<container_name>

# Build info
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/buildinfo | jq .
```

### pvcontrol CLI

The `pvcontrol` tool provides a convenient CLI for common operations:

```bash
# Container lifecycle
docker exec pva-test pvcontrol container ls                       # List containers
docker exec pva-test pvcontrol container stop <container_name>    # Stop container
docker exec pva-test pvcontrol container start <container_name>   # Start container
docker exec pva-test pvcontrol container restart <container_name> # Restart container

# Other operations
docker exec pva-test pvcontrol ls           # List containers (legacy)
docker exec pva-test pvcontrol groups ls    # List container groups
docker exec pva-test pvcontrol buildinfo    # Show build info
docker exec pva-test pvcontrol conf ls      # Show configuration
```

### Process Inspection

```bash
# All processes in appengine
docker exec pva-test ps aux

# Check if pv-xconnect is running
docker exec pva-test ps aux | grep pv-xconnect
```

## Cleanup

### Between Tests

```bash
docker rm -f pva-test
docker volume rm storage-test
```

### Full Cleanup

```bash
# Remove all test containers
docker rm -f pva-test

# Remove test volumes
docker volume rm storage-test

# Remove images
docker rmi pantavisor-appengine:1.0 pantavisor-appengine:latest

# Clean build directory (WARNING: removes all build artifacts)
rm -rf build/tmp-scarthgap
```

## Common Workflows

### Quick Pantavisor Change Test

```bash
# 1. Edit pantavisor source
cd build/workspace/sources/pantavisor
vim xconnect/plugins/drm.c

# 2. Rebuild (from meta-pantavisor root)
cd /path/to/meta-pantavisor
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# 3. Reload docker image
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar

# 4. Test
docker rm -f pva-test; docker volume rm storage-test
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 10
docker exec pva-test lxc-ls -f
```

### Adding a New Example Container

```bash
# 1. Create recipe
cat > recipes-containers/pv-examples/pv-example-mytest_1.0.bb << 'EOF'
SUMMARY = "My Test Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-mytest"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "busybox"

SRC_URI += "file://${PN}.args.json"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/bin/sh"
EOF

# 2. Create args.json
cat > recipes-containers/pv-examples/files/pv-example-mytest.args.json << 'EOF'
{
  "PV_SERVICES_REQUIRED": [
    {"name": "raw", "target": "/run/pv/services/raw.sock"}
  ]
}
EOF

# 3. Build
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-mytest

# 4. Deploy for testing
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-mytest.pvrexport.tgz pvtx.d/
```

### Testing xconnect Plugin Changes

```bash
# 1. Edit plugin
cd build/workspace/sources/pantavisor
vim xconnect/plugins/unix.c

# 2. Build appengine
cd /path/to/meta-pantavisor
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# 3. Reload and test
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
docker rm -f pva-test; docker volume rm storage-test
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 10

# 4. Check xconnect behavior
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
docker exec pva-test ps aux | grep pv-xconnect
```

## Device Configuration (device.json) Pvrexports

Device-level configuration (groups, disks, volumes, network pools) is defined in `device.json`. This can be packaged as a standalone pvrexport that gets merged with container pvrexports during appengine startup.

### Creating a device.json Pvrexport

Unlike container pvrexports which contain rootfs images, device.json pvrexports contain only JSON configuration:

```bitbake
# recipes-containers/pv-examples/pv-example-device-config.bb
SUMMARY = "Device configuration with network pools"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "pvr-native"

inherit pvr-ca

SRC_URI = "file://device.json"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"
PVSTATE = "${WORKDIR}/pvstate"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    :
}

fakeroot do_create_pvrexport() {
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=1

    # Setup signing keys if available
    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        mkdir -p ${PVR_CONFIG_DIR}
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi

    rm -rf ${PVSTATE}
    mkdir -p ${PVSTATE}
    cd ${PVSTATE}
    pvr init

    # Copy device.json directly into state
    cp ${WORKDIR}/device.json device.json

    pvr add
    pvr commit

    mkdir -p ${DEPLOY_DIR_IMAGE}
    pvr export ${DEPLOY_DIR_IMAGE}/${PN}.pvrexport.tgz
}

addtask create_pvrexport after do_install before do_build
do_create_pvrexport[dirs] = "${TOPDIR} ${PVSTATE} ${PVR_CONFIG_DIR}"
do_create_pvrexport[cleandirs] = "${PVSTATE}"
do_create_pvrexport[depends] = "pvr-native:do_populate_sysroot"

PSEUDO_IGNORE_PATHS .= ",${PVSTATE},${PVR_CONFIG_DIR}"
```

### device.json Structure

```json
{
    "groups": [
        {
            "name": "root",
            "status_goal": "STARTED",
            "restart_policy": "container"
        }
    ],
    "disks": [],
    "volumes": {},
    "network": {
        "pools": {
            "internal": {
                "type": "bridge",
                "bridge": "pvbr0",
                "subnet": "10.0.5.0/24",
                "gateway": "10.0.5.1",
                "nat": true
            }
        }
    }
}
```

### Pvrexport Output Structure

The resulting pvrexport tarball contains:
```
json                    # State JSON with device.json embedded
```

The state JSON has this structure:
```json
{
    "#spec": "pantavisor-service-system@1",
    "device.json": {
        "groups": [...],
        "disks": [...],
        "volumes": {...},
        "network": {...}
    }
}
```

### Testing with Appengine

Place the device.json pvrexport alongside container pvrexports in pvtx.d:
```bash
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-*.pvrexport.tgz pvtx.d/
```

Appengine's pvtx will merge them into a single state during startup.

## pv_lxc Dynamic Container Configuration

The `pv_lxc` plugin (`plugins/pv_lxc.c`) dynamically modifies LXC container configuration at runtime before starting containers. This allows pantavisor to augment the static `lxc.container.conf` from the pvrexport with runtime-specific settings.

### Key Function: `pv_setup_lxc_container()`

Located in `plugins/pv_lxc.c:227`, this function is called after loading the static config but before `c->start()`:

```c
c->load_config(c, conf_file);      // Load static lxc.container.conf
pv_setup_lxc_container(c, p, rev); // Dynamic augmentation
c->start(c, 0, NULL);              // Start container
```

### Dynamic Config API

Uses liblxc's `set_config_item()` to add/modify config:

```c
// Add mount entries
c->set_config_item(c, "lxc.mount.entry", "tmpfs /run tmpfs rw 0 0");

// Set network config
c->set_config_item(c, "lxc.net.0.type", "veth");
c->set_config_item(c, "lxc.net.0.link", "pvbr0");
c->set_config_item(c, "lxc.net.0.ipv4.address", "10.0.5.2/24");

// Modify namespace settings
c->set_config_item(c, "lxc.namespace.keep", "user ipc");
```

### Current Dynamic Config

The plugin currently handles:
- `lxc.rootfs.mount` - Sets rootfs mount path
- `lxc.uts.name` - Sets container hostname
- `lxc.cgroup2.devices.allow` - Cgroup v2 device permissions
- `lxc.mount.entry` - Adds mounts for /pantavisor, logs, metadata
- `lxc.hook.mount` - Enables mount hooks (mdev.sh, remount, export.sh)

### pvr Template vs pv_lxc Dynamic Config

| Aspect | pvr Template | pv_lxc Dynamic |
|--------|--------------|----------------|
| When | Build time (pvr app add) | Runtime (container start) |
| What | Static lxc.container.conf | Augments loaded config |
| Use for | Entrypoint, env vars, namespace.keep | Runtime paths, IPAM networking |
| Variables | `PV_LXC_*` template args | Platform struct fields |

### Network Namespace Control

The pvr template controls network namespace via `PV_LXC_NETWORK_TYPE`:

```
# Default (no arg): keeps host network namespace
lxc.namespace.keep = user net ipc

# PV_LXC_NETWORK_TYPE=veth: gets own network namespace
lxc.namespace.keep = user ipc
lxc.net.0.type = veth
lxc.net.0.link = lxcbr0
```

For IPAM pools, set `PV_LXC_NETWORK_TYPE=veth` in args.json to give container its own netns. The pv_lxc plugin should then dynamically configure the actual bridge/IP based on the pool config.

### Platform Network Config

The `pv_platform` struct has network config parsed from run.json:

```c
struct pv_platform {
    ...
    struct pv_platform_network *network; // from run.json "network" field
};

struct pv_platform_network {
    pv_net_mode_t mode;     // NET_MODE_HOST or NET_MODE_POOL
    char *hostname;
    struct dl_list interfaces;  // pv_platform_network_iface list
};

struct pv_platform_network_iface {
    char *pool;           // Pool name from device.json
    char *ipv4_address;   // Allocated IP
    char *bridge;         // Bridge from pool config
    ...
};
```

### IPAM Integration (TODO)

To complete IPAM networking, `pv_setup_lxc_container()` needs to:

1. Check if `p->network` is set with `mode == NET_MODE_POOL`
2. Allocate IP from pool: `pv_ipam_allocate(pool_name, p->name)`
3. Get pool config: `pv_ipam_find_pool(pool_name)->bridge`
4. Configure LXC network dynamically:
   ```c
   c->set_config_item(c, "lxc.net.0.type", "veth");
   c->set_config_item(c, "lxc.net.0.link", pool->bridge);
   c->set_config_item(c, "lxc.net.0.ipv4.address", allocated_ip);
   c->set_config_item(c, "lxc.net.0.ipv4.gateway", pool->gateway);
   c->set_config_item(c, "lxc.net.0.flags", "up");
   ```

## Adding Workspace Packages

When you need to use a local source for a package not already in the workspace (e.g., lxc-pv), create a bbappend file:

```bash
# Create bbappend for lxc-pv
cat > build/workspace/appends/lxc-pv_git.bbappend << 'EOF'
inherit externalsrc
EXTERNALSRC = "${TOPDIR}/workspace/sources/lxc-pv"
EXTERNALSRC_BUILD = "${WORKDIR}/build"
EOF
```

Then clone the source:
```bash
cd build/workspace/sources
git clone https://github.com/pantavisor/lxc.git lxc-pv
cd lxc-pv
git checkout <branch>
```

## Troubleshooting Build Issues

### Stale Build Artifacts

If you see errors about missing files or stale OCI images:
```bash
# Clean specific recipe state
./kas-container shell .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    -c "bitbake -c cleansstate <recipe-name>"

# Example: clean pantavisor-appengine-netsim
./kas-container shell ... -c "bitbake -c cleansstate pantavisor-appengine-netsim"
```

### Source Already Configured

If workspace source has stale configure artifacts:
```bash
cd build/workspace/sources/<package>
git clean -fdx
```

### Docker Image Not Updated

After rebuilding, always reload the docker image:
```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

## Branch Structure

The pantavisor xconnect features are developed in stacked branches:

| Branch | Features | Status |
|--------|----------|--------|
| `feature/xconnect` | Base service mesh (unix, dbus, drm plugins) | PR open |
| `feature/xconnect-landing` | + daemon logging, appengine fixes | PR open |
| `feature/ingress` | + IPAM, auto-recovery, ingress TCP/HTTP | PR open |

When testing, ensure you're on the correct branch for the features you need:
- **xconnect-landing**: Tests 1-4 in TESTPLANS.md (unix, dbus, drm, daemon API)
- **ingress**: IPAM tests, auto-recovery, ingress tests (in that branch's TESTPLANS.md)

## Tips

- Always use `--max-time` with curl to avoid hangs
- Use `pvcurl` instead of `curl` for the pv-ctrl socket (it handles the unix socket correctly)
- Fresh storage volumes prevent stale state issues: `docker volume rm storage-test`
- Interactive mode (`sleep infinity`) gives more control for debugging
- Check both pantavisor.log and container console.log when debugging
- Rebuild AND reload docker image after source changes
- Use `pvr inspect <pvrexport.tgz>` to verify container configuration
