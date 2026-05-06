# xconnect Service-IP Test Plan

Tests for the **service-IP layer** added on top of xconnect: ClusterIP allocation, `<service>.pv.local` DNS, kernel-DNAT fast path (TCP→TCP), userspace proxy (cross-transport), failure semantics, and rollback wiring.

For the legacy unix-socket / D-Bus / DRM xconnect tests, see [testplan-xconnect.md](testplan-xconnect.md). For pv-ctrl API tests, see [testplan-pvctrl.md](testplan-pvctrl.md).

---

## Prerequisites

### Build appengine image with xconnect feature

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Build the test container set

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-svc-tcp-provider \
    --target pv-example-svc-tcp-consumer
```

Future v1.1 fixtures (require features not yet wired in v1, see [Status](#feature-status) below):
- `pv-example-svc-unix-provider` + `pv-example-svc-tcp-to-unix-consumer` (cross-transport)
- `pv-example-svc-failure-readonly` (consumer with read-only `/etc` to drive unhealthy → rollback)
- `pv-example-svc-multi-instance` (two providers offering the same service name → conflict)

### Common setup / teardown

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d
```

```bash
docker rm -f pva-test; docker volume rm storage-test
```

---

## TC-01 — Tier-1 happy path (TCP→TCP kernel forward)

**Purpose**: end-to-end verification that a consumer connects to a TCP service by name (`hello-tcp.pv.local`), packets traverse the `pv-services` bridge, get DNATed in `inet pvx_services`, and reach the provider with no userspace bytes.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-svc-tcp-provider.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-svc-tcp-consumer.pvrexport.tgz pvtx.d/
```

### Execute

```bash
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 20
```

### Assertions

```bash
# Bridge present, ip_forward enabled
docker exec pva-test ip link show pv-services up
docker exec pva-test cat /proc/sys/net/ipv4/ip_forward   # expect: 1

# /xconnect-graph emits cluster_ip + provider_ip + transports
docker exec pva-test sh -c 'curl -s --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph' | jq '.[] | select(.name=="hello-tcp")'
# expect fields: cluster_ip ~ "198.18.x.y", cluster_port=80, provider_ip="10.x.y.z", provider_port=80, provider_transport="tcp"

# nft DNAT rule installed
docker exec pva-test nft list table inet pvx_services
# expect a rule: ip daddr 198.18.x.y tcp dport 80 dnat to 10.x.y.z:80 comment "pvx-services:..."

# /etc/hosts inside the consumer namespace
CONS_PID=$(docker exec pva-test sh -c 'lxc-info -n pv-example-svc-tcp-consumer -p -H')
docker exec pva-test cat /proc/${CONS_PID}/root/etc/hosts | grep hello-tcp.pv.local
# expect: "<cluster_ip>\thello-tcp.pv.local # pvx-services managed"

# Consumer probe is succeeding
sleep 10
docker exec pva-test cat /storage/test-results/tcp-consumer.log | tail -3
# expect lines starting with "<ts> ok ip=198.18.x.y body=hello-tcp v1"
```

### PASS criteria

- All four assertions return the expected lines.
- No "FAIL" line in `tcp-consumer.log` for the last 30 seconds.

### Teardown

```bash
docker rm -f pva-test; docker volume rm storage-test
```

---

## TC-02 — ClusterIP stability across container restart

**Purpose**: verify the ClusterIP for a given service name is deterministic — restarting the provider does not change the ClusterIP, and the consumer reconnects without manifest churn.

### Execute (continuing from TC-01)

```bash
# Capture ClusterIP before restart
CIP_BEFORE=$(docker exec pva-test sh -c 'curl -s --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph' | jq -r '.[] | select(.name=="hello-tcp") | .cluster_ip')

# Stop & restart the provider container only
docker exec pva-test pvcontrol container stop pv-example-svc-tcp-provider
sleep 5
docker exec pva-test pvcontrol container start pv-example-svc-tcp-provider
sleep 10

CIP_AFTER=$(docker exec pva-test sh -c 'curl -s --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph' | jq -r '.[] | select(.name=="hello-tcp") | .cluster_ip')
```

### PASS criteria

- `CIP_BEFORE` == `CIP_AFTER` (deterministic from name, not allocator-state).
- IPAM-allocated `provider_ip` may or may not differ — that's fine, DNAT rule reflects the new value.
- Consumer log resumes "ok" lines within 10s of restart, no manual intervention.

---

## TC-03 — ClusterIP stability across full reboot

**Purpose**: verify ClusterIP is reboot-stable (no on-disk allocator state required).

### Execute

```bash
docker restart pva-test
sleep 30

CIP_REBOOT=$(docker exec pva-test sh -c 'curl -s --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph' | jq -r '.[] | select(.name=="hello-tcp") | .cluster_ip')
```

### PASS criteria

- `CIP_REBOOT` matches `CIP_BEFORE` from TC-01/02.
- nft DNAT rule recomputed with possibly-different `provider_ip` post-reboot, but `cluster_ip` and rule presence identical.
- Consumer log resumes "ok" within 30s.

---

## TC-04 — IPAM coexistence

**Purpose**: confirm `pvipam` (IPAM's table) and `pvx_services` (ours) live side by side without rule leakage.

### Execute

```bash
docker exec pva-test nft list ruleset | grep -E '^table'
# expect both: "table ip nat" (IPAM's MASQUERADE pool) and "table inet pvx_services"

# Cycle the consumer in and out 5x
for i in 1 2 3 4 5; do
    docker exec pva-test pvcontrol container stop pv-example-svc-tcp-consumer
    sleep 3
    docker exec pva-test pvcontrol container start pv-example-svc-tcp-consumer
    sleep 5
done
```

### PASS criteria

- After each cycle, `nft list table inet pvx_services` shows exactly one rule per service (no leak, no orphans).
- `nft list table ip nat` (IPAM) is untouched — rule count constant.
- No "FAIL" lines in `/storage/test-results/tcp-consumer.log` outside the brief stop/start windows.

---

## TC-05 — `xconnect.services.cidr` config override

**Purpose**: verify the `PV_XCONNECT_SERVICES_CIDR` config knob actually changes the ClusterIP range.

### Execute

```bash
# Set a non-default range in pantavisor.config and restart
docker exec pva-test sh -c 'echo "xconnect.services.cidr=10.55.0.0/16" >> /storage/config/pantahub.config'
docker restart pva-test
sleep 30

CIP=$(docker exec pva-test sh -c 'curl -s --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph' | jq -r '.[] | select(.name=="hello-tcp") | .cluster_ip')
```

### PASS criteria

- `CIP` falls within `10.55.0.0/16`, not `198.18.0.0/15`.
- Consumer log shows "ok" entries with the new IP.

---

## Verification log (latest run)

Run on docker-x86_64 appengine, `feat/xconnect-services` branch, build of 2026-05-06 (commits up to and including the network-anchor rejection slice).

| Test | Result | Notes |
|------|--------|-------|
| TC-01 — Tier-1 happy path | ✓ | `cluster_ip=198.18.208.73`, `provider_ip=10.0.5.3`, OUTPUT-chain rule mirrored alongside PREROUTING, 7 consecutive `ok body=hello-tcp v1` after one establishment-race FAIL. |
| TC-02 — ClusterIP stability across container restart | ✓ | `CIP_BEFORE=CIP_AFTER=198.18.208.73` after `pvcontrol containers restart pv-example-svc-tcp-provider`. |
| TC-03 — ClusterIP stability across full reboot | ✓ | `CIP_REBOOT=198.18.208.73` after `docker restart pva-test` + `pv-appengine &`. |
| TC-04 — IPAM coexistence | ✓ | Both `table ip pvx_services` and `table ip nat` present. After 5 cycles of consumer stop/start: 2 dnat lines under `pvx_services` (one per chain — PREROUTING + OUTPUT — no leak; expected new shape since the OUTPUT chain landed). |
| TC-05 — `xconnect.services.cidr` config override | ✓ | Setting `PV_XCONNECT_SERVICES_CIDR=10.55.0.0/16` in `/etc/pantavisor-appengine.config` then restart yields `cluster_ip=10.55.208.73`. **Note**: original testplan pointed at `/storage/config/pantahub.config` for this knob — that file is for pantahub credentials only; runtime daemon knobs live in `/etc/pantavisor-appengine.config` (or the equivalent per init-mode config). |
| TC-10 — Reject service participant without network anchor | ✓ | Log: `platforms.c:pv_platform_start:1206 ... touches xconnect services but declares no network anchor`. Platform never started; cascading `state.c:pv_state_start_platform:644 ... could not be started`. Fixture: `pv-example-svc-tcp-noanchor`. |
| TC-11 — Reject host-mode + no `lxc.net.*` | ✓ | Log: `plugins/pv_lxc.c:pv_validate_container_config:303 ... declares network.mode=host and participates in xconnect services but its lxc.container.conf has no lxc.net.* entries`. Cascading `pv_platform_start:1217 ... refused by backend pre-start validation`. Fixture: `pv-example-svc-tcp-host-bare`. |
| TC-12 — Reject pool + baked `lxc.net.*` (regression) | ✓ | Log: `pv_validate_container_config:296 ... declares an IPAM pool but its lxc.container.conf already contains lxc.net.* entries`. Pre-existing `99e2fba` rule, now hit through service-participant code path. Fixture: `pv-example-svc-tcp-pool-baked`. |

### Notable testplan corrections discovered during this run

1. **Container ops syntax**: use `pvcontrol containers <ls|start|stop|restart> <name>` (not `pvcontrol container <op> <name>` as some earlier drafts had).
2. **API access from inside appengine**: use `pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl <url>`. `curl --unix-socket` is not in the appengine busybox.
3. **Daemon config file path**: `/etc/pantavisor-appengine.config` for `PV_XCONNECT_SERVICES_CIDR` and similar daemon knobs (not `/storage/config/pantahub.config`, which holds Pantahub credentials).
4. **nft table family**: `ip pvx_services`, not `inet pvx_services`. The earlier testplan reference to `inet pvx_services` was speculative.
5. **DNAT rule count after host↔host fix**: each service now installs one rule per chain (PREROUTING + OUTPUT) = 2 dnat lines per established service, not 1. PASS criterion for TC-04 should be "exactly 2 dnat lines per service".

### Earlier verification log (build of 2026-05-04, pre-host↔host fix)

| Assertion | Result |
|-----------|--------|
| `pv-services` bridge up with ClusterIP `/32` | ✓ `198.18.208.73/32 scope global pv-services` |
| `hello-tcp.pv.local` injected into consumer `/etc/hosts` | ✓ `198.18.208.73 hello-tcp.pv.local # pvx-services managed` |
| `/xconnect-graph` emits new fields (`cluster_ip`, `provider_ip`, ports, transports) | ✓ |
| `/xconnect-status` GET returns live link state | ✓ `[{"consumer":...,"name":"hello-tcp","established":true,"last_error":null}]` |
| Sticky-retry on transient parse failure | ✓ link starts unhealthy when pv-ctrl emits `consumer_pid:-1`, becomes established once container pid is real |
| Idempotent rebind across retries | ✓ data-plane (listener, bridge IP) created once, only hosts inject re-runs |
| Consumer end-to-end fetch (`wget hello-tcp.pv.local`) | ✓ verified — once an IPAM pool is declared (the `pv-example-device-ipam` fixture provides pool `internal` 10.0.5.0/24, both test recipes reference it via `PV_NETWORK_POOL`), `provider_ip` becomes 10.0.5.3, the kernel-DNAT fast path activates, and the consumer fetches `hello-tcp v1` over and over: `2026-05-04T21:17:13Z ok ip=198.18.208.73 body=hello-tcp v1` |
| Tier-1 kernel-forward path (zero userspace bytes) | ✓ verified — xconnect log shows `pvx-tcp: kernel-forward 198.18.208.73:80 for service hello-tcp`; nft rule `ip daddr 198.18.208.73 tcp dport 80 dnat to 10.0.5.3:80` installed in `ip pvx_services` table. |

End-to-end TC-01 is fully green when the appengine has an IPAM pool defined. Without IPAM (lxcbr0/Docker default IPs only), the proxy lacks a backend address — that's an integrator-side requirement, not a code limitation.

## Feature status (v1)

What's implemented and exercised by the tests above:

| Feature | Status | Tests |
|---------|--------|-------|
| ClusterIP allocation (FNV-1a → 198.18/15) | ✓ v1 | TC-01, 02, 03 |
| `<service>.pv.local` DNS via /etc/hosts inject | ✓ v1 | TC-01 |
| `pv-services` bridge with ClusterIP /32s | ✓ v1 | TC-01 |
| Tier-1 nft DNAT (TCP→TCP fast path) | ✓ v1 | TC-01, 02 |
| `xconnect.services.cidr` config override | ✓ v1 | TC-05 |
| Reboot-stable ClusterIP | ✓ v1 | TC-03 |
| IPAM coexistence | ✓ v1 | TC-04 |

What's wired structurally but **not yet exercised end-to-end** in v1:

| Feature | Status | Deferred test |
|---------|--------|---------------|
| Tier-2 userspace proxy (cross-transport) | code in `xconnect/plugins/tcp.c`; consumer-side `consumer_transport` override missing in graph emission | TC-06 (TBD): unix backend + TCP front |
| Hard-fail link establishment → unhealthy signal | `last_error` set, sticky retry; pv-ctrl status endpoint not yet wired | TC-07 (TBD): readonly /etc consumer → rollback |
| Multi-backend conflict detection | not implemented; deferred to v2 with `services` block in device.json | TC-08 (TBD) |
| Platform health gate (`pv_platform_start` queries link status) | not yet wired; needs xconnect→pv-ctrl status push | TC-09 (TBD) |

When those features land, add the corresponding TCs and test container fixtures.

---

## TC-10 — Reject service participant without network anchor

**Purpose**: verify that a container exporting a service via
`services.json` (or requiring one via `services.required`) and **not**
declaring a network anchor (no `network.pool`, no `network.mode=host`)
is refused at platform start. The status-goal must time out and the
revision must fail to reach READY.

### Setup

Build a fixture variant of `pv-example-svc-tcp-provider` with
`PV_NETWORK_POOL` *removed* from `args.json` so the rendered `run.json`
has no `network` block. Stage as the only service container in
`pvtx.d/`.

### Execute

```bash
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 25
```

### Assertions

```bash
# Platform must NOT be running
docker exec pva-test sh -c 'pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/platforms' | jq '.[] | select(.name=="pv-example-svc-tcp-provider") | .status.current'
# expect: not "STARTED" or "READY"

# Pantavisor logs the refusal
docker exec pva-test sh -c 'pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl "http://localhost/cgi-bin/logs?source=pantavisor&tail=200"' | grep -i "touches xconnect services but declares no network anchor"
# expect: one match, naming the platform
```

### PASS criteria

- Platform start refused with the documented log line.
- Status goal eventually times out (revision fails to reach READY).
- No nft DNAT rule installed for the rejected platform's services.

---

## TC-11 — Reject host-net service participant without lxc.net.\*

**Purpose**: verify that a container declaring `network.mode=host` AND
participating in xconnect services AND lacking any `lxc.net.*` lines in
its `lxc.container.conf` is refused at platform start.

### Setup

Build a fixture variant of `pv-example-svc-tcp-provider` whose `run.json`
declares `"network": { "mode": "host" }` and whose `lxc.container.conf`
contains no `lxc.net.*` entries.

### Execute

Same boot sequence as TC-10.

### Assertions

```bash
docker exec pva-test sh -c 'pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl "http://localhost/cgi-bin/logs?source=pantavisor&tail=200"' | grep -i "host-net service participants must bring their own network config"
# expect: one match, naming the platform
```

### PASS criteria

- Platform start refused with the documented log line.
- Status goal eventually times out.

---

## TC-12 — Pool participant with baked lxc.net.\* (regression for `99e2fba`)

**Purpose**: regression for the existing rule that a pool participant
must not bake `lxc.net.*` into its conf, now hit through a service
participant rather than a plain IPAM-only container.

### Setup

Build a fixture combining `PV_NETWORK_POOL=internal` with a
`lxc.container.conf` that already contains `lxc.net.0.type = veth`.

### Assertions

```bash
docker exec pva-test sh -c 'pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl "http://localhost/cgi-bin/logs?source=pantavisor&tail=200"' | grep -i "declares an IPAM pool but its lxc.container.conf already contains lxc.net"
# expect: one match
```
