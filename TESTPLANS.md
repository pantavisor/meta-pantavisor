# Appengine Test Plans (xconnect-landing)

This document provides executable test plans for validating pv-xconnect service mesh in the appengine environment.

**Branch**: `feature/xconnect-landing`
**Features tested**: pv-xconnect service mesh (unix, dbus, drm plugins), daemon management API

> **Note**: Tests for IPAM, auto-recovery, and ingress features are in the `feature/ingress` branch.

## Prerequisites

### Build Appengine Image

```bash
# Standard build (uses upstream repos)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

# Build with local workspace (uses local branches of pantavisor, lxc, etc.)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

**Note**: Use `kas/with-workspace.yaml` when testing local changes in `build/workspace/sources/` (e.g., pantavisor, lxc-pv). This overlay adds the workspace layer and enables xconnect features.

### Common Setup

```bash
# Clean previous state
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null

# Prepare pvtx.d directory
mkdir -p pvtx.d
```

### Common Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

---

## Test 1: Unix Socket Service Mesh

**Purpose**: Verify pv-xconnect injects Unix sockets between provider and consumer containers.

### Setup

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-client.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check both containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING, pv-example-unix-client RUNNING

# Check xconnect graph
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
# Expected: JSON with type=unix, consumer=pv-example-unix-client

# Check socket injected into consumer
CLIENT_PID=$(docker exec pva-test lxc-info -n pv-example-unix-client -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$CLIENT_PID/root/run/pv/services/
# Expected: raw.sock socket file
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| xconnect-graph | Shows unix link |
| Injected socket | `/run/pv/services/raw.sock` exists in client |

---

## Test 2: D-Bus Service Mesh

**Purpose**: Verify pv-xconnect D-Bus proxy with role-to-UID mapping.

### Setup

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-dbus-server \
    --target pv-example-dbus-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-dbus-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-dbus-client.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-dbus-server RUNNING, pv-example-dbus-client RUNNING

# Check client logs for successful D-Bus call
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log | tail -20
# Expected: method return with org.pantavisor.Example response
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| D-Bus call | Successful method return in client logs |

---

## Test 3: DRM Device Injection

**Purpose**: Verify pv-xconnect injects DRM device nodes into consumer containers.

**Note**: Requires VKMS kernel module or real GPU hardware.

### Setup

```bash
# Load VKMS on host (if no real GPU)
sudo modprobe vkms

./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-drm-provider \
    --target pv-example-drm-master

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-provider.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-drm-master.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    --device /dev/dri:/dev/dri \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-drm-provider RUNNING, pv-example-drm-master RUNNING

# Check DRM device in consumer
MASTER_PID=$(docker exec pva-test lxc-info -n pv-example-drm-master -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$MASTER_PID/root/dev/dri/
# Expected: card0 device node
```

### Expected Results

| Check | Expected |
|-------|----------|
| Provider status | RUNNING |
| Master status | RUNNING |
| DRM device | `/dev/dri/card0` exists in master container |

---

## Test 4: Daemon Start/Stop API

**Purpose**: Verify the `/daemons` API can stop and start managed daemons like pv-xconnect.

### Setup

```bash
# Any container set will work, using unix examples
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-client.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# List all daemons
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons | jq .
# Expected: JSON array with pv-xconnect and other daemons, showing PID and respawn status

# Check pv-xconnect is running
docker exec pva-test ps aux | grep pv-xconnect
# Expected: pv-xconnect process visible

# Stop pv-xconnect
docker exec pva-test pvcurl -X PUT --data '{"action":"stop"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect | jq .
# Expected: {"status":"stopped"} or similar

# Verify stopped
docker exec pva-test ps aux | grep pv-xconnect
# Expected: No pv-xconnect process

# Check daemons API shows stopped
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons | jq .
# Expected: pv-xconnect with pid=-1 or respawn=false

# Start pv-xconnect again
docker exec pva-test pvcurl -X PUT --data '{"action":"start"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect | jq .
# Expected: {"status":"started"} or similar

# Verify running again
sleep 2
docker exec pva-test ps aux | grep pv-xconnect
# Expected: pv-xconnect process visible again
```

### Expected Results

| Check | Expected |
|-------|----------|
| GET /daemons | JSON list with daemon info |
| Stop daemon | Process terminates, respawn disabled |
| Start daemon | Process restarts, respawn enabled |

---

## Quick Test Commands

### Check Container Status
```bash
docker exec pva-test lxc-ls -f
```

### Check Pantavisor Logs
```bash
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -50
```

### Check Container Logs
```bash
docker exec pva-test cat /var/pantavisor/storage/logs/0/<container>/lxc/console.log
```

### Check xconnect Graph
```bash
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
```

### Enter Container
```bash
docker exec -it pva-test pventer -c <container>
```

### Fresh Restart
```bash
docker rm -f pva-test; docker volume rm storage-test
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| pvtx.d not processed | Storage volume reused | Delete volume: `docker volume rm storage-test` |
| Container not starting | Check pantavisor.log | Look for ERROR lines |
| xconnect-graph empty | pv-xconnect not running | Check `ps aux \| grep pv-xconnect` |
| Socket not injected | Provider not ready | Wait longer, check provider status |
