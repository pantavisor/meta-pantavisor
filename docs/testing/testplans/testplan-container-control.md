# Container Lifecycle Control Test Plan

Tests for the `PUT /containers/{name}` API using existing xconnect example containers.

For xconnect service mesh tests, see [testplan-xconnect.md](testplan-xconnect.md).
For pv-ctrl API tests, see [testplan-pvctrl.md](testplan-pvctrl.md).

---

## Prerequisites

### Build Appengine Image and Example Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client \
    --target pv-example-cleanexit \
    --target pv-example-app
```

**Container overview:**

| Container | restart_policy | auto_recovery | SIGTERM handling | Purpose |
|-----------|---------------|---------------|------------------|---------|
| `pv-example-unix-server` | `container` | none | No (socat in fork mode) | Lifecycle control target, tests force-stop after grace timeout |
| `pv-example-unix-client` | `system` | none | N/A | System-policy rejection test |
| `pv-example-cleanexit` | `container` | `on-failure` | No | Batch job that exits cleanly after 5s |
| `pv-example-app` | `container` | none | Yes (shell trap) | Tests lenient stop path (graceful exit via SIGTERM) |

```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Common Setup

```bash
docker rm -f pva-test 2>/dev/null
docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-client.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-cleanexit.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-app.pvrexport.tgz pvtx.d/

docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Common Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

---

## Test 1: Reject Stop on System-Policy Container

**Purpose**: Verify containers with `restart_policy: "system"` cannot be stopped via API.

### Execute

```bash
# Confirm both containers are running
docker exec pva-test pvcontrol ls
# Expected: unix-server with restart_policy "container", unix-client with "system"

# Try to stop the system-policy container
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-unix-client
# Expected: HTTP 403 (forbidden — system containers cannot be stopped via API)
```

### Verify

```bash
# Container should still be running
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-client RUNNING

# Also test nonexistent container
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/nonexistent-container
# Expected: HTTP 404
```

### Expected Results

| Check | Expected |
|-------|----------|
| System-policy stop | HTTP 403 (forbidden by policy) |
| Container still running | Yes |
| Unknown container | HTTP 404 |

---

## Test 2: Stop a Container (container policy)

**Purpose**: Verify stopping a container with `restart_policy: "container"` via the API.
Verify that `user_stopped` flag is set and auto-recovery does not restart the container.

### Execute

```bash
# Confirm container is running with container policy
docker exec pva-test pvcontrol ls
# Expected: pv-example-unix-server restart_policy "container", status STARTED

# Stop the container
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-unix-server
# Expected: HTTP 200 OK
```

### Verify

```bash
# Check container status
docker exec pva-test pvcontrol ls
# Expected: pv-example-unix-server status = STOPPED

docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server STOPPED

# Check user_stopped flag
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A20 unix-server
# Expected: "user_stopped": "true"

# Verify container stays stopped (auto-recovery not triggered)
sleep 10
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server still STOPPED
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| Container status | STOPPED |
| user_stopped flag | true |
| Stays stopped | Yes (user_stopped prevents auto-recovery) |

---

## Test 3: Start a Stopped Container

**Purpose**: Verify starting a previously stopped container clears `user_stopped` and restores auto-recovery.

### Execute

```bash
# Container should be stopped from Test 2
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server STOPPED

# Start it
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"start"}' http://localhost/containers/pv-example-unix-server
# Expected: HTTP 200 OK

sleep 5
```

### Verify

```bash
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING

docker exec pva-test pvcontrol ls
# Expected: pv-example-unix-server status = STARTED

# Check user_stopped is cleared
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A20 unix-server
# Expected: "user_stopped": "false"
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| Container status | RUNNING / STARTED |
| user_stopped flag | false |

---

## Test 4: Restart a Running Container

**Purpose**: Verify restart performs force_stop + auto-recovery restart with reset retries.

### Execute

```bash
# Get current PID
docker exec pva-test pvcontrol ls
# Note the pid value for pv-example-unix-server

# Restart
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"restart"}' http://localhost/containers/pv-example-unix-server
# Expected: HTTP 200 OK

sleep 10
```

### Verify

```bash
docker exec pva-test pvcontrol ls
# Expected: pv-example-unix-server STARTED with a different (new) pid

docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING

# user_stopped should be false
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A20 unix-server
# Expected: "user_stopped": "false", "current_retries": 0 or 1
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| New PID | Different from pre-restart PID |
| Container status | RUNNING |
| user_stopped | false |

---

## Test 5: Restart a Stopped Container

**Purpose**: Verify restart works on an already-stopped container.

### Execute

```bash
# Stop first
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-unix-server
sleep 3

docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server STOPPED

# Now restart from stopped state
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"restart"}' http://localhost/containers/pv-example-unix-server
# Expected: HTTP 200 OK

sleep 5
```

### Verify

```bash
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING

docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A20 unix-server
# Expected: "user_stopped": "false"
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| Container status | RUNNING |
| user_stopped | false |

---

## Test 6: GET /containers JSON Structure

**Purpose**: Verify GET /containers returns correct JSON structure per container type.

### Execute

```bash
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | python3 -m json.tool
```

### Expected Results

| Container | restart_policy | auto_recovery object | user_stopped field |
|-----------|---------------|---------------------|-------------------|
| unix-server | "container" | Absent (RECOVERY_NO) | Present: "false" |
| unix-client | "system" | Absent (RECOVERY_NO) | Absent (system policy) |
| cleanexit | "container" | Present with policy "on-failure" | Present: "false" |

**Note**: `auto_recovery` is omitted entirely for containers with no recovery policy.
`user_stopped` is a top-level field only present on `restart_policy: "container"` containers.

---

## Test 7: No Mount Accumulation on Restart Cycles

**Purpose**: Verify that volumes are unmounted on stop and remounted on start,
with no mount accumulation after multiple restart cycles.

### Execute

```bash
# Get baseline mount count
docker exec pva-test cat /proc/mounts | grep unix-server | wc -l
# Expected: 2 (root.squashfs + lxc-overlay)

# Perform 3 restart cycles
for i in 1 2 3; do
    docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
        --data '{"action":"restart"}' http://localhost/containers/pv-example-unix-server 2>/dev/null
    sleep 5
done

docker exec pva-test cat /proc/mounts | grep unix-server | wc -l
# Expected: 2 (same as baseline — no accumulation)
docker exec pva-test cat /proc/mounts | grep unix-server
```

### Verify

```bash
# Also verify stop+start cycle doesn't accumulate
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-unix-server 2>/dev/null
sleep 2

# Volumes should be unmounted while stopped
docker exec pva-test cat /proc/mounts | grep unix-server | wc -l
# Expected: 0 (all unmounted)

docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"start"}' http://localhost/containers/pv-example-unix-server 2>/dev/null
sleep 5

docker exec pva-test cat /proc/mounts | grep unix-server | wc -l
# Expected: 2 (fresh mounts, no accumulation)
```

### Expected Results

| Check | Expected |
|-------|----------|
| Mounts after 3 restarts | 2 (no accumulation) |
| Mounts while stopped | 0 (all unmounted) |
| Mounts after start | 2 (fresh mount) |

---

## Test 8: Batch Job — Stop, Start, Restart Cycle

**Purpose**: Verify the cleanexit batch job container can be stopped during its
auto-recovery cycle and re-run via start or restart with reset retries.

**Note**: `on-failure` currently does not distinguish exit codes — a clean exit (0)
still triggers auto-recovery. The cleanexit container uses `backoff_policy: "never"`
so it will eventually stop permanently after exhausting `max_retries`.

### Execute

```bash
# Stop cleanexit to prevent it from cycling (it may be in RECOVERING state)
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-cleanexit 2>/dev/null
sleep 2

# Verify stopped
docker exec pva-test lxc-ls -f | grep cleanexit
# Expected: STOPPED

# Restart it — should reset retries and start fresh
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"restart"}' http://localhost/containers/pv-example-cleanexit 2>/dev/null

sleep 2
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    if c['name'] == 'pv-example-cleanexit':
        ar = c.get('auto_recovery', {})
        print(f'status={c[\"status\"]}, retries={ar.get(\"current_retries\",\"N/A\")}')"
# Expected: status=STARTED, retries=0

# Stop it before it cycles through max_retries
sleep 5
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-cleanexit 2>/dev/null

# Now start (not restart) — should also reset retries
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"start"}' http://localhost/containers/pv-example-cleanexit 2>/dev/null
sleep 2
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | python3 -c "
import sys, json
for c in json.load(sys.stdin):
    if c['name'] == 'pv-example-cleanexit':
        ar = c.get('auto_recovery', {})
        print(f'status={c[\"status\"]}, retries={ar.get(\"current_retries\",\"N/A\")}')"
# Expected: status=STARTED, retries=0

# Stop to prevent cycling
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-cleanexit 2>/dev/null
```

### Expected Results

| Check | Expected |
|-------|----------|
| Restart resets retries | current_retries=0, status=STARTED |
| Start resets retries | current_retries=0, status=STARTED |
| Stop prevents cycling | Container stays STOPPED |

---

## Test 9: Lenient Stop (SIGTERM-Aware Container)

**Purpose**: Verify that containers which handle SIGTERM shut down gracefully
via the lenient stop path (no force-kill needed). Contrasts with containers
like `pv-example-unix-server` that ignore the shutdown signal and fall through
to the 5-second grace-period force-stop.

### Execute

```bash
# pv-example-app has a SIGTERM trap — exits cleanly
docker exec pva-test lxc-ls -f | grep pv-example-app
# Expected: RUNNING

# Stop it — should exit quickly (before 5s grace timeout)
start=$(date +%s)
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"stop"}' http://localhost/containers/pv-example-app
# Poll until STOPPED
for i in $(seq 1 10); do
    s=$(docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
        http://localhost/containers 2>/dev/null | \
        python3 -c "import sys,json; [print(c['status']) for c in json.load(sys.stdin) if c['name']=='pv-example-app']")
    [ "$s" = "STOPPED" ] && break
    sleep 1
done
end=$(date +%s)
echo "Stop took $((end - start))s"
# Expected: < 5s (graceful SIGTERM exit, not timeout force-stop)
```

### Verify

```bash
# Container stays stopped (user_stopped prevents auto-recovery)
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | python3 -m json.tool | grep -A2 pv-example-app
# Expected: status=STOPPED, user_stopped=true

# Check pantavisor log for the lenient stop path
docker exec pva-test cat /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | \
    grep -E "(lenient|exited during lenient|force stopping)" | tail -5
# Expected: "leniently stopping platform 'pv-example-app'"
#           "platform 'pv-example-app' exited during lenient stop"
# NOT expected: "did not exit after lenient stop, force stopping"
```

### Expected Results

| Check | Expected |
|-------|----------|
| Stop duration | < 5s (graceful) |
| Container status | STOPPED |
| user_stopped | true |
| Log path | "exited during lenient stop" (not timeout force-stop) |

### Compare with unix-server (no SIGTERM handler)

`pv-example-unix-server` runs `socat` in fork mode and does not handle the LXC
shutdown signal (SIGPWR). Stopping it takes ~5 seconds — the lenient stop is
initiated, the engine waits for the grace-period timer, then force-stops. Both
containers end up STOPPED with `user_stopped: true`, but through different paths.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| 403 on stop (expected for Test 1) | restart_policy is "system" | Correct — system containers cannot be stopped |
| 403 on stop (unexpected for Test 2) | args.json not picked up | Rebuild with clean storage volume |
| Container restarts after stop | user_stopped not set | Check pantavisor SRCREV matches workspace |
| Missing user_stopped in GET | Old pantavisor build | Rebuild with workspace overlay |
| pvcurl hangs | Connection not closing | Add timeout or use `-o /dev/null` |
| Mounts accumulate on restart | Missing volume unmount fix | Ensure pantavisor includes PLAT_STOPPED unmount |
| Mounts != 0 while stopped | Unmount failed (e.g., busy) | Check for processes holding mount points |
| Cleanexit keeps cycling | on-failure treats exit 0 as failure | Expected — use stop API to break cycle |
