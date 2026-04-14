# Auto-Recovery Test Plan

Tests for container auto-recovery with exponential backoff via the appengine environment.

For xconnect service mesh tests, see [testplan-xconnect.md](testplan-xconnect.md).
For pv-ctrl API tests, see [testplan-pvctrl.md](testplan-pvctrl.md).

---

## Prerequisites

### Example Containers

| Container | Group | policy | max_retries | backoff_policy |
|-----------|-------|--------|-------------|----------------|
| `pv-example-recovery` | root | on-failure | 3, delay 5s, factor 2x | 10min |
| `pv-example-stabilize` | root | on-failure | 3 | reboot |
| `pv-example-random` | root | always | — | never |
| `pv-example-app-crash` | app | inherited from group | 5, delay 5s, factor 2x | reboot |

`pv-example-app-crash` uses `PVR_APP_ADD_GROUP = "app"` in its recipe and inherits the default `app` group auto-recovery policy from `device.json`.

### Build Appengine Image and Test Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-recovery \
    --target pv-example-stabilize \
    --target pv-example-random \
    --target pv-example-app-crash

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

## Test 4: Group-Level Auto-Recovery Inheritance

**Purpose**: Verify a container without `auto_recovery` in its `run.json` inherits the group's default auto-recovery policy from `device.json`.

### Setup

This test uses a custom `device.json` that adds `auto_recovery` to the `root` group, and a container that has **no** `PV_AUTO_RECOVERY` in its `args.json`.

```bash
rm -f pvtx.d/*.pvrexport.tgz
# Use a container without auto_recovery (e.g., a plain busybox container)
# The group-level auto_recovery in device.json will apply
```

**device.json group config:**
```json
{
    "name": "root",
    "restart_policy": "container",
    "status_goal": "STARTED",
    "timeout": 30,
    "auto_recovery": {
        "policy": "on-failure",
        "max_retries": 3,
        "retry_delay": 2,
        "backoff_factor": 1.5,
        "stable_timeout": 15,
        "backoff_policy": "never"
    }
}
```

### Verify

```bash
# Check pantavisor log for inherited auto-recovery
docker exec pva-test grep -i "auto-recovery\|attempt\|STABLE" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -10

# Check pvcontrol shows inherited values
docker exec pva-test pvcontrol ls
# Expected: auto_recovery.max_retries = 3, stable_timeout = 15
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container has no auto_recovery in run.json | No `PV_AUTO_RECOVERY` in args.json |
| Inherited from group | pvcontrol shows max_retries=3, stable_timeout=15 |
| Recovery works | Container restarts on crash with group's policy |
| All-or-nothing | All fields come from group, not mixed with defaults |

---

## Test 5: Container Auto-Recovery Overrides Group

**Purpose**: Verify a container with its own `auto_recovery` in `run.json` does NOT inherit from the group — all-or-nothing semantics.

### Setup

Use a group with `auto_recovery` AND a container with its own `PV_AUTO_RECOVERY` (e.g., `pv-example-recovery`).

### Verify

```bash
docker exec pva-test pvcontrol ls
# Expected: container's own values (max_retries=5, stable_timeout=30),
# NOT the group's values
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container has auto_recovery | Its own values used |
| Group also has auto_recovery | Group values ignored |
| max_retries | Container's value (5), not group's |

---

## Test 6: Stable Timeout Prevents Premature Commit

**Purpose**: Verify that during TESTING, the commit is held until all containers with `stable_timeout` have survived their stability window.

### Verify

```bash
# Check pantavisor log during an update
docker exec pva-test grep -i "commit held\|STABLE\|commit" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -10
# Expected: "commit held: waiting for all containers to become stable"
# followed by "is now STABLE" and then commit
```

### Expected Results

| Check | Expected |
|-------|----------|
| Commit timer expires | Commit not immediate |
| stable_timeout pending | "commit held" log message |
| Container survives window | "is now STABLE" log message |
| Then commit | `pv_update_set_final()` proceeds |

---

## Test 7: Backoff Policy "never" — Container Stays Stopped

**Purpose**: Verify `backoff_policy: "never"` leaves a container stopped after max_retries without triggering a system reboot.

### Verify

```bash
# After max_retries exhausted:
docker exec pva-test grep -i "backoff_policy.*never\|leaving.*stopped\|recovery_failed" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -5
# Expected: "backoff_policy=never — leaving 'container' stopped"

docker exec pva-test lxc-ls -f
# Expected: container STOPPED, system still running (no reboot)
```

### Expected Results

| Check | Expected |
|-------|----------|
| Container status | STOPPED |
| System state | Still running, no reboot |
| Log message | "backoff_policy=never" |
| Other containers | Unaffected, still running |

---

## Test 8: Backoff Policy Duration — Retry Cycle Reset

**Purpose**: Verify `backoff_policy: "10min"` waits the configured duration after max_retries, then resets the retry counter and restarts recovery.

### Verify

```bash
# After max_retries exhausted:
docker exec pva-test grep -i "backoff_policy.*600\|scheduling.*retry\|recovery.*timer.*finished" \
    /var/pantavisor/storage/logs/0/pantavisor/pantavisor.log | tail -5
# Expected: "backoff_policy=600s — scheduling retry cycle reset"
# After 600s: "recovery timer finished" and new attempt 1/N
```

### Expected Results

| Check | Expected |
|-------|----------|
| After max_retries | "scheduling retry cycle reset" |
| Container status | RECOVERING (waiting 600s) |
| After duration | Retry counter resets, new recovery cycle starts |
| New attempts | "attempt 1/5" logged again |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Container not restarting | auto_recovery not parsed | Check pantavisor.log for parsing errors |
| No backoff visible | Timer not working | Check for `RECOVERING` status in pvcontrol ls |
| Stabilize never stabilizes | Overlay not persisted | Verify lxc-overlay persistence is `boot` in run.json |
| Too many retries | max_retries exceeded | Container stays STOPPED after max failures |
