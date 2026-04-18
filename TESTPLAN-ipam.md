# IPAM Networking Test Plan

Tests for IPAM (IP Address Management) pool-based container networking via the appengine environment.

---

## Prerequisites

### Build Appengine Image and Test Containers

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-device-ipam \
    --target pv-example-net-server \
    --target pv-example-net-client \
    --target pv-example-ipam-valid \
    --target pv-example-ipam-invalid \
    --target pv-example-ipam-collision \
    --target pantavisor-appengine

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Common Setup

The `pv-example-device-ipam` pvrexport provides the `device.json` with IPAM pool
definitions. It must be included in `pvtx.d/` alongside container pvrexports so that
`pvtx add` merges the device.json into the trail during appengine startup.

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

## Test 1: Basic IPAM Pool Allocation

**Purpose**: Verify containers referencing an IPAM pool get automatic IP allocation from the configured subnet.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-client.pvrexport.tgz pvtx.d/
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
# Check both containers are running with IPs from 10.0.5.0/24
docker exec pva-test lxc-ls -f
# Expected: net-server and net-client RUNNING with 10.0.5.x IPs

# Check device.json was loaded with pool config
docker exec pva-test cat /var/pantavisor/storage/trails/0/device.json
# Expected: network.pools.internal with subnet 10.0.5.0/24

# Check IPAM log messages
docker exec pva-test grep -i "ipam\|pool\|allocated" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
# Expected: pool 'internal' added, IPs allocated to each container

# Check bridge was created
docker exec pva-test ip addr show pvbr0
# Expected: pvbr0 bridge with 10.0.5.1/24
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | Both RUNNING |
| net-client IP | 10.0.5.x (auto-allocated from pool) |
| net-server IP | 10.0.5.x (auto-allocated from pool) |
| Bridge pvbr0 | Created with gateway 10.0.5.1/24 |
| IPAM log | "added pool 'internal'", "allocated 10.0.5.x" |

---

## Test 2: Static IP Assignment

**Purpose**: Verify a container can request a specific static IP from the pool.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-valid.pvrexport.tgz pvtx.d/
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
docker exec pva-test lxc-ls -f
# Expected: pv-example-ipam-valid RUNNING with 10.0.5.50

docker exec pva-test grep "allocated" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
# Expected: allocated 10.0.5.50 to pv-example-ipam-valid
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | RUNNING |
| Assigned IP | 10.0.5.50 (static, as requested in args.json) |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No IPs assigned | Missing device.json | Ensure pv-example-device-ipam.pvrexport.tgz is in pvtx.d |
| "pool not found" | device.json not parsed | Check pantavisor.log for device.json parsing |
| NAT not working | iptables missing in appengine | Expected in docker, containers can still communicate on bridge |
| Bridge not created | IPAM init failed | Check for "IPAM subsystem initialized" in log |
