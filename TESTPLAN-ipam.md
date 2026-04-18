# IPAM Networking Test Plan

Tests for IPAM (IP Address Management) pool-based container networking via the appengine environment.

---

## Prerequisites

### Build Appengine Image and Test Containers

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-device-ipam \
    --target pv-example-device-ipam-2pools \
    --target pv-example-net-server \
    --target pv-example-net-lab-server \
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

## Test 3: Two pools, NAT vs no-NAT

**Purpose**: Verify each pool's `nat` flag independently controls outbound MASQUERADE. One pool with `nat: true` can reach external hosts; one with `nat: false` cannot (source IPs aren't translated and are not routable beyond the bridge).

The `device-ipam-2pools` export defines:

| Pool | Bridge | Subnet | NAT |
|------|--------|--------|-----|
| `internal` | `pvbr0` | 10.0.5.0/24 | `true` |
| `lab`      | `pvbr1` | 10.0.6.0/24 | `false` |

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam-2pools.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-lab-server.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 20
```

### Verify

```bash
# Both containers running with IPs from their respective pools
docker exec pva-test lxc-ls -f

# Only the internal pool got a MASQUERADE rule
docker exec pva-test nft list ruleset

# Outbound from internal (nat=true) — should succeed
docker exec pva-test pventer -c pv-example-net-server ping 8.8.8.8 -c 2

# Outbound from lab (nat=false) — should 100% loss (no MASQUERADE)
docker exec pva-test pventer -c pv-example-net-lab-server ping 8.8.8.8 -c 2

# Same-pool intra-subnet — should succeed on lab despite no NAT
docker exec pva-test pventer -c pv-example-net-lab-server ping 10.0.6.1 -c 2
```

### Expected Results

| Check | Expected |
|-------|----------|
| `nft list ruleset` | Single MASQUERADE entry for 10.0.5.0/24 on pvbr0 (no rule for pvbr1) |
| net-server (internal) → 8.8.8.8 | 0% packet loss |
| net-lab-server (lab) → 8.8.8.8 | 100% packet loss |
| net-lab-server → 10.0.6.1 (gateway) | 0% packet loss (bridge-local, no NAT needed) |
| IPAM log | `added pool 'internal': ..., nat=yes` and `added pool 'lab': ..., nat=no`; `setup NAT (nftables) for pool internal` appears but no such line for `lab` |

**Note**: With the current IPAM implementation there is no cross-pool isolation — `internal → lab` (e.g. `ping 10.0.6.2` from net-server) will succeed because the kernel's FORWARD chain defaults to ACCEPT. Cross-pool isolation is a separate feature (tracked for a follow-up).

---

## Test 4: NAT backend selection (nftables preferred)

**Purpose**: Verify pantavisor's `setup_nat` probes `command -v nft` and `command -v iptables` and prefers nftables when both are available, falling back to iptables only if nft is missing or fails.

The appengine image ships with `nftables` installed (`iptables` is **not** included — nftables is sufficient on every distro kernel from 2014 onwards).

### Verify backend selection

Re-use the Test 1 or Test 3 setup; after `pv-appengine` is running, inspect the IPAM log:

```bash
docker exec pva-test grep "setup NAT" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
# Expected: "setup NAT (nftables) for pool <name>"
# No "(iptables)" lines, and no warnings about missing nft/iptables.
```

The nft ruleset should show a `table ip nat` with a `postrouting` chain of `srcnat` priority:

```bash
docker exec pva-test nft list ruleset
```

### Verify iptables fallback (optional)

To exercise the fallback path you would need a variant appengine image that ships `iptables` but not `nftables`, and confirm the log then says `setup NAT (iptables) for pool <name>`. This isn't covered by the default appengine image.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No IPs assigned | Missing device.json | Ensure pv-example-device-ipam.pvrexport.tgz is in pvtx.d |
| "pool not found" | device.json not parsed | Check pantavisor.log for device.json parsing |
| "failed to setup NAT" in log | iptables/nftables missing in appengine image | Rebuild appengine image (iptables and nftables are pulled in by default via `CORE_IMAGE_EXTRA_INSTALL`) |
| Bridge not created | IPAM init failed | Check for "IPAM subsystem initialized" in log |
