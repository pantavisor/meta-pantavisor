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
    --target pv-example-ipam-nopool \
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

## Test 6: IPAM lease stability across stop/start

**Purpose**: Verify that stopping and starting a container via the container-control API (`pvcontrol containers stop` / `start`) keeps the container's IPAM-assigned IP stable. The same expectation applies to the auto-recovery restart path — a container that crashes and is restarted by `pv_state_check_auto_recovery` also comes back with the same IP.

The lease is keyed by `(pool_name, container_name)` and `pv_ipam_allocate` reuses any existing lease before allocating a new IP, so the IP persists across any lifecycle transition that doesn't destroy the platform (container-control stop/start, auto-recovery retries). Platform teardown (`pv_platform_free`, on state transition / reboot / rollback) does release the lease; that is intentional.

### Setup

Reuse the Test 1 single-pool setup (`pv-example-device-ipam` + `pv-example-net-server`).

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-server.pvrexport.tgz pvtx.d/

docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 20
```

### Execute + verify

```bash
# 1) Baseline — record the running container's IP
docker exec pva-test lxc-ls -f
# Expected: pv-example-net-server RUNNING with 10.0.5.2

# 2) Stop via the container-control API
docker exec pva-test pvcontrol containers stop pv-example-net-server
sleep 10
docker exec pva-test lxc-ls -f
# Expected: pv-example-net-server STOPPED (IPv4 column is blank)

# 3) Start again via the API
docker exec pva-test pvcontrol containers start pv-example-net-server
sleep 10
docker exec pva-test lxc-ls -f
# Expected: pv-example-net-server RUNNING with 10.0.5.2 (same as baseline)

# 4) The IPAM log confirms the lease was reused, not re-allocated
docker exec pva-test grep "reusing existing lease\|allocated 10.0.5" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
# Expected to see exactly one "allocated 10.0.5.2/24 to pv-example-net-server"
# line from the initial start, followed by a "reusing existing lease for
# pv-example-net-server: 10.0.5.2/24" line from the post-stop restart.
```

### Expected Results

| Check | Expected |
|-------|----------|
| IP before stop | 10.0.5.2 |
| State after stop | STOPPED |
| IP after start | 10.0.5.2 (unchanged) |
| IPAM log | one `allocated` line + one `reusing existing lease` line |

### Auto-recovery note

The same `pv_ipam_allocate` reuse-by-name logic is taken when the auto-recovery path restarts a crashed container (both the delayed-retry branch via `timer_retry` and the immediate-retry branch — see the `fix(ipam): keep IPAM lease stable across auto-recovery restarts` commit that removed the pre-restart `pv_ipam_release()` on the immediate branch). A future expansion of this test could use a purpose-built crashing recipe to exercise that path end-to-end; for now the invariant is covered by code review plus this stop/start check, which drives the same allocate-with-reuse code path.

---

## Test 7: Revision rejected on unknown pool reference

**Purpose**: Verify pantavisor refuses the revision when any container declares `PV_NETWORK_POOL` referencing a pool that is not defined in `device.json`. In an in-progress update this propagates through `pv_state_run → _pv_run` into `PV_STATE_ROLLBACK`; in steady state into `PV_STATE_REBOOT`. The check is performed at `pv_platform_start` time and short-circuits before any namespace / LXC work happens.

The `pv-example-ipam-nopool` recipe ships with `PV_NETWORK_POOL: "does-not-exist"` and reuses the minimal `inherit image` template — it is a ~2.7 MB pvrexport with just busybox and a defensive idle-loop entrypoint (the entrypoint should never actually run).

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-device-ipam.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-net-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-ipam-nopool.pvrexport.tgz pvtx.d/

docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 25
```

### Verify

```bash
# No containers running — the revision was torn down
docker exec pva-test lxc-ls -f
# Expected: empty output

# The pantavisor log confirms the refuse + teardown sequence
docker exec pva-test grep -E \
    "unknown pool|failed IPAM network validation|did not work as expected" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log
# Expected sequence (each pv_state_run tick retries and logs again):
#   ERROR [platforms] ... references unknown pool 'does-not-exist', refusing to start
#   ERROR [platforms] ... failed IPAM network validation, triggering rollback if in try-boot
#   ERROR [controller] ... a platform did not work as expected. Tearing down...
```

### Expected Results

| Check | Expected |
|-------|----------|
| `lxc-ls -f` | Empty — no containers running (including the well-formed `pv-example-net-server` in the same revision) |
| Pantavisor log | The three ERROR lines above appear in order |
| `pv_state_run` return | Non-zero — propagates into `_pv_run` which goes to `PV_STATE_ROLLBACK` (in TESTING) or `PV_STATE_REBOOT` (steady state) |

### Notes

- The `pv_platform_start` bubble-up is the single error-handling path — no separate validate step. The same mechanism catches volume-mount and driver-load failures.
- `pv_state_run`'s platform loop does not break on first error, so other platforms in the same revision may briefly attempt their starts before the overall return value triggers teardown. They still end up torn down; the only cost is a few extra log lines per tick.

---

## Test 8: Pool-using container with baked `lxc.net.*` is refused

**Purpose**: Verify that a container which declares an IPAM pool AND bakes `lxc.net.*` entries into its `lxc.container.conf` is refused at start time via the backend plugin's `validate_config` hook. The error bubbles up the same way as an unknown-pool reference — `pv_state_run → _pv_run → PV_STATE_ROLLBACK` in a TESTING update.

**Policy** (see [Pantavisor IPAM overview](https://github.com/pantavisor/pantavisor/blob/master/docs/overview/ipam.md#pre-start-validation)): if a container opts into an IPAM pool, it must let pantavisor own its network namespace. Pantavisor injects its own `lxc.net.0.*` from the allocated IP/MAC/bridge at start time; silently overwriting a user-baked `lxc.net.0` would leak orphan attributes (e.g. stale `lxc.net.0.macvlan.mode` after type is rewritten to veth).

`lxc.namespace.keep = net` is **not** treated as a conflict — pvr's default template includes it, and pantavisor strips `net` from the keep list at runtime.

### Verification approach

Constructing a signed pvrexport with `lxc.net.*` baked in requires a recipe-level post-processing step that is not shipped today (the default `pvr app add` does not produce `lxc.net.*` entries). Two ways to exercise this test:

#### Option A — code review (recommended default)

- Confirm `plugins/pv_lxc.c:pv_validate_container_config` scans for a prefix `lxc.net.` after trimming leading whitespace and skipping comments.
- Confirm `platforms.c:pv_platform_start` calls `ctrl->validate_config(p, path)` before the IPAM allocation block and returns `-1` on non-zero.
- Confirm the dlsym in `load_pv_plugin` wires `pv_validate_container_config` into `cont_ctrl[].validate_config`.

#### Option B — manual reproduction

In a non-signed development build, stop pantavisor, append `lxc.net.0.type = veth` to a pool-using container's `lxc.container.conf` in the trail, and restart pantavisor. (On a signed production build this fails signature verification first, which is a different error path — useful as a regression guard but not for exercising the `validate_config` hook.)

### Expected log

```
ERROR [pv_lxc]: pv_validate_container_config: platform '<name>' declares an IPAM pool but its lxc.container.conf already contains lxc.net.* entries — pantavisor will not overwrite them. Remove the baked lxc.net.* config, or drop the PV_NETWORK_POOL reference.
ERROR [platforms]: pv_platform_start: platform '<name>' refused by backend pre-start validation
ERROR [state]: pv_state_start_platform: platform <name> could not be started
ERROR [controller]: _pv_wait: a platform did not work as expected. Tearing down...
```

And `docker exec pva-test lxc-ls -f` shows no containers running.

### Regression guard

Re-running Tests 1-7 must still pass — the validation only fires when:
1. The container declares `PV_NETWORK_POOL` (→ `p->network->mode == NET_MODE_POOL`), and
2. The baked `lxc.container.conf` contains a line starting with `lxc.net.`.

Default pvr-generated containers have no `lxc.net.*` lines, so the check is a no-op for them.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No IPs assigned | Missing device.json | Ensure pv-example-device-ipam.pvrexport.tgz is in pvtx.d |
| "pool not found" | device.json not parsed | Check pantavisor.log for device.json parsing |
| "failed to setup NAT" in log | iptables/nftables missing in appengine image | Rebuild appengine image (iptables and nftables are pulled in by default via `CORE_IMAGE_EXTRA_INSTALL`) |
| Bridge not created | IPAM init failed | Check for "IPAM subsystem initialized" in log |
