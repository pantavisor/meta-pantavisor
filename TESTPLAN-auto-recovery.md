# Auto-Recovery Test Plan

Tests for container auto-recovery with exponential backoff via the appengine environment.

For xconnect service mesh tests, see [TESTPLAN-xconnect.md](TESTPLAN-xconnect.md).
For pv-ctrl API tests, see [TESTPLAN-pvctrl.md](TESTPLAN-pvctrl.md).

---

## Prerequisites

### Build Appengine Image and Test Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-recovery \
    --target pv-example-stabilize \
    --target pv-example-random

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

## Test 1: On-Failure Recovery with Exponential Backoff

**Purpose**: Verify a container with `policy: "on-failure"` is automatically restarted with increasing delays.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-recovery.pvrexport.tgz pvtx.d/
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
# Check container is running (first cycle)
docker exec pva-test lxc-ls -f
# Expected: pv-example-recovery RUNNING

# Check auto-recovery config in container status
docker exec pva-test pvcontrol ls
# Expected: auto_recovery.type = "on-failure", max_retries = 5

# Wait for first crash and recovery (container exits after ~10s, retry_delay=5s)
sleep 20

# Check container logs for restart evidence
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-recovery/lxc/console.log
# Expected: Multiple "Recovery test container starting..." entries

# Check pantavisor log for recovery messages
docker exec pva-test grep -i "recover" /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -10
# Expected: auto-recovery messages with increasing retry counts
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | RUNNING or RECOVERING |
| auto_recovery.type | `on-failure` |
| Console log | Multiple startup lines showing restarts |
| Retry count | Increments after each crash |
| Backoff | Delays increase (5s, 10s, 20s with factor 2.0) |

---

## Test 2: Stabilize Pattern (Failing then Stable)

**Purpose**: Verify a container that fails 3 times then stabilizes is restarted correctly and eventually stays running.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-stabilize.pvrexport.tgz pvtx.d/
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
# Wait for stabilization (3 failures at ~5s each + retry delays, then stable)
sleep 60

# Check container is RUNNING and staying up
docker exec pva-test lxc-ls -f
# Expected: pv-example-stabilize RUNNING

# Check console log for progression
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-stabilize/lxc/console.log
# Expected: "Run #1" through "Run #4", with #4 saying "stable phase"

# Check retry count has reset (after reset_window=300s, or still shows retries)
docker exec pva-test pvcontrol ls
# Expected: container STARTED, auto_recovery shows current_retries
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | RUNNING (stable after run #4) |
| Console log runs | Run #1, #2, #3 fail; Run #4+ stays running |
| Persistent state | Boot count stored in /var/lib/boot_count via lxc-overlay |
| Final behavior | `sleep infinity` — container stays up |

---

## Test 3: Always-Restart with Random Timing

**Purpose**: Verify `policy: "always"` keeps restarting a container regardless of exit code.

### Setup

```bash
rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-random.pvrexport.tgz pvtx.d/
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
# Wait for a few restart cycles (random 10-30s sleep + retry delays)
sleep 90

# Check container is still being managed
docker exec pva-test lxc-ls -f
# Expected: pv-example-random RUNNING or RECOVERING

# Check console log shows multiple restarts
docker exec pva-test cat /var/pantavisor/storage/logs/0/pv-example-random/lxc/console.log
# Expected: Multiple "Random restart container starting..." lines

# Verify max_retries=10 is respected
docker exec pva-test pvcontrol ls
# Expected: auto_recovery.current_retries incrementing, max_retries=10
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | RUNNING or RECOVERING (continuously) |
| auto_recovery.type | `always` |
| Console log | Multiple restart cycles with varying sleep times |
| Retry behavior | Keeps restarting up to max_retries=10 |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container not restarting | auto_recovery not parsed | Check pantavisor.log for parsing errors |
| No backoff visible | Timer not working | Check for `RECOVERING` status in pvcontrol ls |
| Stabilize never stabilizes | Overlay not persisted | Verify lxc-overlay persistence is `boot` in run.json |
| Too many retries | max_retries exceeded | Container stays STOPPED after max failures |
