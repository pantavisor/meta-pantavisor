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

## Pantavisor Development

### Initial Setup

First build initializes the workspace:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
```

The pantavisor source is now at:
```
build/workspace/sources/pantavisor/
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
   [
     {"name": "my-service", "type": "unix", "socket": "/run/my-service.sock"}
   ]
   ```

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
docker exec pva-test cat /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log
```

### Container Logs

```bash
docker exec pva-test cat /run/pantavisor/pv/logs/0/<container_name>/lxc/console.log
```

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

```bash
# xconnect graph
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .

# Container status
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers | jq .

# Build info
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/buildinfo | jq .
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

## Tips

- Always use `--max-time` with curl to avoid hangs
- Use `stdbuf -oL` when running commands that need unbuffered output
- Fresh storage volumes prevent stale state issues
- Interactive mode (`sleep infinity`) gives more control for debugging
- Check both pantavisor.log and container console.log when debugging
