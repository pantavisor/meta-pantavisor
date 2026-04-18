# xconnect Service Mesh Test Plan

Tests for pv-xconnect container-to-container communication via the appengine environment.

For pv-ctrl API tests (daemons, graph, metadata, objects, etc.), see [TESTPLAN-pvctrl.md](TESTPLAN-pvctrl.md).

---

## Prerequisites

### Build Appengine Image

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Common Setup

```bash
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
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
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
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
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check both containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING, pv-example-unix-client RUNNING

# Check xconnect graph
docker exec pva-test pvcontrol graph ls
# Expected: JSON with type=unix, consumer=pv-example-unix-client

# Check socket injected into consumer
CLIENT_PID=$(docker exec pva-test lxc-info -n pv-example-unix-client -p | awk '{print $2}')
docker exec pva-test ls -la /proc/$CLIENT_PID/root/run/pv/services/
# Expected: raw-unix.sock socket file
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| xconnect graph | Shows unix link between server and client |
| Injected socket | `/run/pv/services/raw-unix.sock` exists in client |

---

## Test 2: D-Bus Service Mesh

**Purpose**: Verify pv-xconnect D-Bus proxy with role-to-UID mapping.

### Setup

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
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
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

```bash
# Check containers running
docker exec pva-test lxc-ls -f
# Expected: pv-example-dbus-server RUNNING, pv-example-dbus-client RUNNING

# Check xconnect graph
docker exec pva-test pvcontrol graph ls
# Expected: JSON with type=dbus link

# Check client logs for successful D-Bus call
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-dbus-client/lxc/console.log | tail -20
# Expected: method return with org.pantavisor.Example response
```

### Expected Results

| Check | Expected |
|-------|----------|
| Server status | RUNNING |
| Client status | RUNNING |
| xconnect graph | Shows dbus link between server and client |
| D-Bus call | Successful method return in client logs |

---

## Test 3: DRM Device Injection

**Purpose**: Verify pv-xconnect injects DRM device nodes into consumer containers.

**Note**: Requires VKMS kernel module or real GPU hardware.

### Setup

```bash
# Load VKMS on host (if no real GPU)
sudo modprobe vkms

./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
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
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

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

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| pvtx.d not processed | Storage volume reused | Delete volume: `docker volume rm storage-test` |
| Container not starting | Check pantavisor.log | `docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log` |
| xconnect-graph empty | pv-xconnect not running | `docker exec pva-test pvcontrol daemons ls` |
| Socket not injected | Provider not ready | Wait longer, check provider status |
