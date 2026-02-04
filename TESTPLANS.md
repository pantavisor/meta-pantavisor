# Appengine Test Plans

This document provides executable test plans for validating pv-examples containers in the appengine environment.

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

## Test 1: IPAM Validation - Invalid Static IP

**Purpose**: Verify that containers with static IPs outside the pool subnet are refused and trigger rollback.

### Setup

```bash
# Build required containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config \
    --target pv-example-ipam-invalid

# Deploy to pvtx.d
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-invalid.pvrexport.tgz pvtx.d/
```

### Execute

```bash
# Start appengine
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
# Check IPAM pool was loaded
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "added pool 'internal'"
# Expected: [ipam]: added pool 'internal': type=bridge, subnet=10.0.3.0/24, gateway=10.0.3.1, nat=yes

# Check invalid IP was rejected
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "IP 192.168.99.100 not in pool"
# Expected: [ipam]: IP 192.168.99.100 not in pool 'internal' subnet

# Check container was refused
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "refusing to start|triggering rollback"
# Expected:
#   failed to reserve static IP 192.168.99.100 ... refusing to start
#   platform 'pv-example-ipam-invalid' failed IPAM network validation, triggering rollback if in try-boot

# Verify container is NOT running
docker exec pva-test lxc-ls -f | grep pv-example-ipam-invalid
# Expected: No output (container not running)
```

### Expected Results

| Check | Expected |
|-------|----------|
| Pool loaded | `added pool 'internal': type=bridge, subnet=10.0.3.0/24` |
| IP rejected | `IP 192.168.99.100 not in pool 'internal' subnet` |
| Container refused | `refusing to start` + `triggering rollback` |
| Container status | Not in `lxc-ls` output |

---

## Test 2: IPAM Validation - Valid Static IP

**Purpose**: Verify that containers with valid static IPs within the pool subnet start successfully.

### Setup

```bash
# Build required containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config \
    --target pv-example-ipam-valid

# Deploy to pvtx.d (clean first)
rm -f pvtx.d/pv-example-ipam-*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/
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
# Check container is running with correct IP
docker exec pva-test lxc-ls -f | grep pv-example-ipam-valid
# Expected: pv-example-ipam-valid RUNNING ... 10.0.3.50

# Check IP was reserved
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "reserved.*10.0.3.50|static IP.*10.0.3.50"
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | RUNNING |
| Container IP | 10.0.3.50 |

---

## Test 3: IPAM Validation - IP Collision

**Purpose**: Verify that two containers requesting the same static IP results in the second being refused.

### Setup

```bash
# Build required containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config \
    --target pv-example-ipam-valid \
    --target pv-example-ipam-collision

# Deploy to pvtx.d
rm -f pvtx.d/pv-example-ipam-*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-collision.pvrexport.tgz pvtx.d/
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
# Check one container running, one refused
docker exec pva-test lxc-ls -f | grep pv-example-ipam
# Expected: Only ONE of the two containers running

# Check collision detected
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "already in use"
# Expected: failed to reserve static IP 10.0.3.50 ... (already in use or outside subnet)
```

### Expected Results

| Check | Expected |
|-------|----------|
| First container | RUNNING with 10.0.3.50 |
| Second container | Refused (already in use) |

---

## Test 4: Unix Socket Service Mesh

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
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
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

## Test 5: D-Bus Service Mesh

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

## Test 6: DRM Device Injection

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

## Test 7: Daemon Start/Stop API

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
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons | jq .
# Expected: JSON array with pv-xconnect and other daemons, showing PID and respawn status

# Check pv-xconnect is running
docker exec pva-test ps aux | grep pv-xconnect
# Expected: pv-xconnect process visible

# Stop pv-xconnect
docker exec pva-test curl -s --max-time 3 -X PUT \
    --data '{"action":"stop"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect | jq .
# Expected: {"status":"stopped"} or similar

# Verify stopped
docker exec pva-test ps aux | grep pv-xconnect
# Expected: No pv-xconnect process

# Check daemons API shows stopped
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons | jq .
# Expected: pv-xconnect with pid=0 or respawn=false

# Start pv-xconnect again
docker exec pva-test curl -s --max-time 3 -X PUT \
    --data '{"action":"start"}' \
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

## Test 8: Auto-Recovery Container

**Purpose**: Verify the auto-recovery feature with exponential backoff on container failure.

The `pv-example-recovery` container:
- Runs for 10 seconds, then exits with failure (exit 1)
- Has `PV_AUTO_RECOVERY` config: on-failure policy, max 5 retries, 5s initial delay, 2x backoff

### Setup

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-recovery

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-recovery.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 20
```

### Verify

```bash
# Check container logs - should show multiple restarts
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-recovery/lxc/console.log
# Expected:
#   Recovery test container starting...
#   I will sleep for 10 seconds and then exit with failure (1).
#   Exiting now!
#   (repeated multiple times)

# Check pantavisor logs for recovery events
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -iE "recovery|retry|backoff|pv-example-recovery.*(restart|fail|exit)"
# Expected: Messages about container failure, retry attempts, backoff delays

# Watch live recovery behavior (container restarts every ~10s + backoff delay)
docker exec pva-test lxc-ls -f
# Run multiple times to see container cycling through RUNNING -> STOPPED -> RUNNING

# After max retries exhausted, check final state
sleep 120  # Wait for all retries with backoff
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -iE "max.*retries|exhausted|giving up"
# Expected: Message about max retries reached
```

### Expected Results

| Check | Expected |
|-------|----------|
| Initial status | RUNNING (for ~10s) |
| After exit | Container restarts automatically |
| Backoff | Delay increases: 5s, 10s, 20s, 40s... |
| Max retries | After 5 failures, recovery stops |
| Console log | Multiple "starting/exiting" cycles |

---

## Test 9: Container Restart Policy

**Purpose**: Verify container restart policies (system vs container) work correctly.

### Setup

```bash
# Build containers with different restart policies
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-device-config \
    --target pv-example-ipam-valid

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-config.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/
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
# Check container is running
docker exec pva-test lxc-ls -f | grep pv-example-ipam-valid
# Expected: RUNNING

# Get container PID
CONTAINER_PID=$(docker exec pva-test lxc-info -n pv-example-ipam-valid -p | awk '{print $2}')
echo "Container init PID: $CONTAINER_PID"

# Kill the container's init process (simulate crash)
docker exec pva-test kill -9 $CONTAINER_PID

# Wait for restart (container restart_policy)
sleep 10

# Check if container restarted
docker exec pva-test lxc-ls -f | grep pv-example-ipam-valid
# Expected: RUNNING (with new PID)

# Verify new PID
NEW_PID=$(docker exec pva-test lxc-info -n pv-example-ipam-valid -p | awk '{print $2}')
echo "New container init PID: $NEW_PID"
# Expected: Different PID than before
```

### Expected Results

| Check | Expected |
|-------|----------|
| Initial status | RUNNING |
| After kill | Container restarts automatically |
| restart_policy=container | Container restarts, no system rollback |

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
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
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
| "pool not found" | device.json not deployed | Add pv-example-device-config to pvtx.d |

---

## Test 10: Direct Integrated Ingress

**Purpose**: Verify that global ingress rules defined in `device.json` correctly match and bind host ports.

### Setup
Build and deploy `pv-example-device-config-direct` along with backend servers.

### Verify

**1. Check Graph**
Check `xconnect-graph` for `EXTERNAL` consumer matching `pv-example-unix-server` and `pv-example-rest-server`.
```bash
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
```

**2. End-to-End Connectivity (TCP 2222)**
Send a message to host port 2222 and expect an echo from the unix server.
```bash
docker exec pva-test sh -c "echo 'HELLO WORLD' | nc -w 2 localhost 2222"
# Expected: HELLO WORLD
```

**3. End-to-End Connectivity (HTTP 80/api)**
Request the API route on host port 80.
```bash
docker exec pva-test sh -c "printf 'GET /api HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' | nc localhost 80"
# Expected: HTTP/1.1 200 OK (followed by mock JSON response)
```


---

## Test 11: Isolated Hybrid Proxy Ingress

**Purpose**: Verify that host ports can be mapped to an isolated proxy container (Pattern 2b).

**Status**: PASS (TCP backend implementation completed 2026-01-27)

### Setup

```bash
# Build required containers
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-nginx-ingress

# Prepare test directory with hybrid device config
mkdir -p pvtx.d-ingress-test
cp recipes-containers/pv-examples/files/device.json.ingress-hybrid pvtx.d-ingress-test/device.json
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-nginx-ingress.pvrexport.tgz pvtx.d-ingress-test/

# Start appengine
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d-ingress-test:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Verify

**1. Check Container Running with IPAM**
```bash
docker exec pva-test lxc-ls -f
# Expected: example-nginx-ingress RUNNING ... 10.0.4.2 ...
```

**2. Check Direct Access to Container**
```bash
docker exec pva-test wget -q -O - http://10.0.4.2:80/ | head -5
# Expected: <!DOCTYPE html> ... Welcome to nginx! ...
```

**3. Check xconnect-graph**
```bash
docker exec pva-test sh -c 'echo -e "GET /xconnect-graph HTTP/1.0\r\nHost: localhost\r\n\r\n" | nc -U /run/pantavisor/pv/pv-ctrl' | tail -1 | jq .
# Expected: Shows EXTERNAL consumer with constructed socket address:
#   "socket": "10.0.4.2:80" (container IP from IPAM + port from services.json)
```

**4. Check Ingress Listener Binding**
```bash
docker exec pva-test cat /proc/net/tcp | head -5
# Expected: 00000000:0050 (0.0.0.0:80) in LISTEN state
```

**5. End-to-End Connectivity (Hybrid Port 80)**
```bash
docker exec pva-test wget -q -O - --timeout=3 http://127.0.0.1:80/
# Expected: <!DOCTYPE html> ... Welcome to nginx!
```

### Test Results (2026-01-27)

| Check | Result | Notes |
|-------|--------|-------|
| IPAM networking | ✅ PASS | Container gets 10.0.4.2/24 |
| Container running | ✅ PASS | nginx running in isolated namespace |
| Direct HTTP access | ✅ PASS | wget to 10.0.4.2:80 works |
| xconnect-graph | ✅ PASS | Shows socket: "10.0.4.2:80" |
| Ingress listener | ✅ PASS | 0.0.0.0:80 bound by pv-xconnect |
| End-to-end proxy | ✅ PASS | HTTP via localhost:80 returns nginx page |

### Implementation Notes

TCP backend connection support was added to enable Pattern 2b ingress:

1. **Parser** (`parser/parser_system1.c`): Now parses `"port"` field from services.json
2. **Platforms** (`platforms.c`): Added `pv_platform_get_ipv4_address()` helper
3. **State** (`state.c`): Constructs `<ip>:<port>` socket address for TCP services
4. **TCP Plugin** (`xconnect/plugins/tcp.c`): Supports both TCP and Unix socket backends

See `xconnect/TCP-BACKEND.md` for implementation details.

