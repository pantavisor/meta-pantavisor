# Container Lifecycle Control Test Plan

Tests for the `PUT /containers/{name}` API using existing xconnect example containers.

For xconnect service mesh tests, see [TESTPLAN-xconnect.md](TESTPLAN-xconnect.md).
For pv-ctrl API tests, see [TESTPLAN-pvctrl.md](TESTPLAN-pvctrl.md).

---

## Prerequisites

### Build Appengine Image and Example Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client
```

**Note**: `pv-example-unix-server` has `restart_policy: "container"` (set via args.json),
while `pv-example-unix-client` inherits the group default `restart_policy: "system"`.
This allows testing both positive lifecycle control and negative system-policy rejection.

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

# Verify container stays stopped (auto-recovery disabled by stop action)
sleep 10
docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server still STOPPED
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| Container status | STOPPED |
| Stays stopped | Yes (auto-recovery disabled by stop action) |

---

## Test 3: Start a Stopped Container

**Purpose**: Verify starting a previously stopped container.

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
# Expected: pv-example-unix-server status = STARTED, pid > 0
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| Container status | RUNNING / STARTED |
| PID | Non-zero |

---

## Test 4: Restart a Running Container

**Purpose**: Verify restart performs stop + start atomically.

### Execute

```bash
# Get current PID
docker exec pva-test pvcontrol ls
# Note the pid value for pv-example-unix-server

# Restart
docker exec pva-test pvcurl -X PUT --unix-socket /run/pantavisor/pv/pv-ctrl \
    --data '{"action":"restart"}' http://localhost/containers/pv-example-unix-server
# Expected: HTTP 200 OK

sleep 5
```

### Verify

```bash
docker exec pva-test pvcontrol ls
# Expected: pv-example-unix-server STARTED with a different (new) pid

docker exec pva-test lxc-ls -f
# Expected: pv-example-unix-server RUNNING
```

### Expected Results

| Check | Expected |
|-------|----------|
| API response | HTTP 200 |
| New PID | Different from pre-restart PID |
| Container status | RUNNING |

---

## Test 5: Enhanced Container Status Query

**Purpose**: Verify GET /containers returns pid, uptime, restart_policy, provides, and consumes.

### Execute

```bash
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null
```

### Verify

```bash
# Check response has expected fields for a running container:
# - name, group, status, status_goal
# - pid (non-zero for running containers)
# - uptime_secs
# - restart_policy ("container" for unix-server, "system" for unix-client)
# - auto_recovery object
# - provides array (for unix-server)
# - consumes array (for unix-client)

# Server should have provides entries
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A5 provides

# Client should have consumes entries
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl \
    http://localhost/containers 2>/dev/null | grep -A5 consumes
```

### Expected Results

| Check | Expected |
|-------|----------|
| pid field | Non-zero for running containers |
| uptime_secs | Positive integer |
| restart_policy | "container" for unix-server, "system" for unix-client |
| provides (server) | Array with unix service entry |
| consumes (client) | Array with required service entry |
| auto_recovery | Object with type, max_retries fields |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| 403 on stop (expected for Test 1) | restart_policy is "system" | Correct — system containers cannot be stopped |
| 403 on stop (unexpected for Test 2) | args.json not picked up | Rebuild with clean storage volume |
| Container doesn't restart | auto-recovery disabled by stop | Use "start" action to re-enable |
| Missing fields in GET | Old pantavisor SRCREV | Ensure container-control branch is built |
| pvcurl hangs | Connection not closing | Add timeout or use `-o /dev/null` |
