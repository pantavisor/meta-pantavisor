# Pantavisor Control API Test Plan

Comprehensive test plan for the pv-ctrl REST API and `pvcontrol` CLI wrapper.

**Branch**: `feature/xconnect-landing`
**Scope**: All pv-ctrl endpoints exposed via Unix socket at `/run/pantavisor/pv/pv-ctrl`

---

## Prerequisites

### Build Appengine Image

```bash
# Build with workspace overlay (for testing local pantavisor changes)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# Build example containers for xconnect tests
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pv-example-unix-server \
    --target pv-example-unix-client

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Launch Appengine

```bash
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d

rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-server.pvrexport.tgz pvtx.d/
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-unix-client.pvrexport.tgz pvtx.d/

docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

./tools/testing/pva exec sh -c 'pv-appengine &'
sleep 15
```

### Helper Tool

All tests use `tools/pva` — a single tool for appengine interaction:

```bash
./tools/testing/pva exec <cmd> [args...]        # Run command inside appengine container
./tools/testing/pva pvc [pvcurl-args...] <url>  # Query pv-ctrl API via pvcurl
```

### Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

---

## Test 1: Build Info

**Endpoint**: `GET /buildinfo`

### Execute

```bash
./tools/testing/pva exec pvcontrol buildinfo
```

### Expected

- Returns plain text build manifest (may be empty in appengine builds)
- HTTP 200 OK

---

## Test 2: Containers List

**Endpoint**: `GET /containers`

### Execute

```bash
./tools/testing/pva pvc http://localhost/containers
```

### Expected

- JSON array with container entries
- Each container has: `name`, `group`, `status`, `restart_policy`, `roles`
- With unix examples loaded: `pv-example-unix-server` and `pv-example-unix-client` present
- Status should be `STARTED` for running containers

---

## Test 3: Groups List

**Endpoint**: `GET /groups`

### Execute

```bash
./tools/testing/pva pvc http://localhost/groups
```

### Expected

- JSON array listing container groups
- Should include at least: `data`, `root`, `platform`
- Appengine with examples loaded should show `app` group

---

## Test 4: Steps List

**Endpoint**: `GET /steps`

### Execute

```bash
./tools/testing/pva pvc http://localhost/steps
```

### Expected

- JSON array of revision objects
- Should include at least revision `0` (initial state)

---

## Test 5: Steps Get State

**Endpoint**: `GET /steps/{name}`

### Execute

```bash
# Get current state
./tools/testing/pva pvc http://localhost/steps/current

# Get specific revision
./tools/testing/pva pvc http://localhost/steps/0
```

### Expected

- Returns full state.json for the revision
- JSON with container definitions, platform config, etc.
- `current` returns the active revision's state

---

## Test 6: Steps Show Progress

**Endpoint**: `GET /steps/{name}/progress`

### Execute

```bash
./tools/testing/pva pvc http://localhost/steps/0/progress
```

### Expected

- JSON with progress information
- Contains `status` field (e.g., `DONE` for completed revisions)

---

## Test 7: Configuration

**Endpoints**: `GET /config`, `GET /config2`

### Execute

```bash
# Legacy config (with aliases)
./tools/testing/pva pvc http://localhost/config

# Full config
./tools/testing/pva pvc http://localhost/config2
```

### Expected

- `/config` returns config with aliased key names
- `/config2` returns full configuration object
- Both return JSON with pantavisor config key-value pairs
- Should include entries like `system.init.mode`, `log.level`, etc.

---

## Test 8: Device Metadata CRUD

**Endpoints**: `GET /device-meta`, `PUT /device-meta/{key}`, `DELETE /device-meta/{key}`

### Execute

```bash
# List current device metadata
./tools/testing/pva pvc http://localhost/device-meta

# Save a new key
./tools/testing/pva pvc -X PUT --data 'test-value-123' http://localhost/device-meta/test-key

# Verify it was saved
./tools/testing/pva pvc http://localhost/device-meta

# Save with different value (update)
./tools/testing/pva pvc -X PUT --data 'updated-value-456' http://localhost/device-meta/test-key

# Verify update
./tools/testing/pva pvc http://localhost/device-meta

# Delete the key
./tools/testing/pva pvc -X DELETE http://localhost/device-meta/test-key

# Verify deletion
./tools/testing/pva pvc http://localhost/device-meta
```

### Expected

| Step | Expected |
|------|----------|
| Initial ls | JSON object (contains auto-populated keys like `pantavisor.arch`) |
| After save | `test-key` appears with value `test-value-123` |
| After update | `test-key` value is `updated-value-456` |
| After delete | `test-key` no longer present |

---

## Test 9: User Metadata CRUD

**Endpoints**: `GET /user-meta`, `PUT /user-meta/{key}`, `DELETE /user-meta/{key}`

### Execute

```bash
# List current user metadata
./tools/testing/pva pvc http://localhost/user-meta

# Save a key
./tools/testing/pva pvc -X PUT --data 'my-value' http://localhost/user-meta/my-key

# Verify
./tools/testing/pva pvc http://localhost/user-meta

# Update
./tools/testing/pva pvc -X PUT --data 'new-value' http://localhost/user-meta/my-key

# Verify
./tools/testing/pva pvc http://localhost/user-meta

# Delete
./tools/testing/pva pvc -X DELETE http://localhost/user-meta/my-key

# Verify
./tools/testing/pva pvc http://localhost/user-meta
```

### Expected

| Step | Expected |
|------|----------|
| Initial ls | JSON object (typically empty `{}` in fresh appengine) |
| After save | `my-key` with value `my-value` |
| After update | `my-key` with value `new-value` |
| After delete | `my-key` no longer present |

---

## Test 10: Device Metadata - Delete Non-Existent Key

**Endpoint**: `DELETE /device-meta/{key}`

### Execute

```bash
./tools/testing/pva pvc -X DELETE http://localhost/device-meta/nonexistent-key-xyz
```

### Expected

- HTTP 404 NOT FOUND response

---

## Test 11: Objects List

**Endpoint**: `GET /objects`

### Execute

```bash
./tools/testing/pva pvc http://localhost/objects
```

### Expected

- JSON array of object SHA256 hashes
- With containers loaded, should return multiple object hashes

---

## Test 12: Objects PUT - Small File

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
# Create a small test file
./tools/testing/pva exec sh -c 'echo "hello pvctrl test" > /tmp/test-small.txt'

# Compute SHA256
./tools/testing/pva exec sha256sum /tmp/test-small.txt

# Upload (use SHA from previous step)
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-small.txt http://localhost/objects/<SHA>

# Verify it appears in listing
./tools/testing/pva pvc http://localhost/objects
```

### Expected

- Upload succeeds with HTTP 200 OK
- Object hash appears in objects listing

---

## Test 13: Objects PUT - Large File (Chunked Upload)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
# Create 2MB test file
./tools/testing/pva exec dd if=/dev/urandom of=/tmp/test-2mb.bin bs=1024 count=2048

# Compute SHA256
./tools/testing/pva exec sha256sum /tmp/test-2mb.bin

# Upload (use SHA from previous step)
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-2mb.bin http://localhost/objects/<SHA>

# Verify
./tools/testing/pva pvc http://localhost/objects
```

### Expected

- Upload succeeds with HTTP 200 OK
- Object stored correctly (verified by hash in listing)
- Pantavisor log shows chunked upload: `incoming data: <bytes>` messages followed by `upload done`

---

## Test 14: Objects GET - Download and Verify Integrity

**Endpoint**: `GET /objects/{sha256}`

### Execute

```bash
# Download (use SHA from Test 13)
./tools/testing/pva pvc -o /tmp/test-2mb-downloaded.bin http://localhost/objects/<SHA>

# Verify integrity
./tools/testing/pva exec sha256sum /tmp/test-2mb.bin
./tools/testing/pva exec sha256sum /tmp/test-2mb-downloaded.bin
```

### Expected

- Download succeeds
- SHA256 checksums match between original and downloaded file

---

## Test 15: Objects PUT - Wrong Hash (Checksum Validation)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
./tools/testing/pva exec sh -c 'echo "checksum test" > /tmp/test-badsha.txt'

# Use a wrong hash
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-badsha.txt \
    http://localhost/objects/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### Expected

- Upload fails with HTTP 422 UNPROCESSABLE ENTITY
- Object is NOT stored (bad checksum rejected)

---

## Test 16: Objects PUT - Duplicate Upload (Idempotency)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
./tools/testing/pva exec sh -c 'echo "duplicate test" > /tmp/test-dup.txt'
./tools/testing/pva exec sha256sum /tmp/test-dup.txt

# Upload first time (use SHA from previous step)
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-dup.txt http://localhost/objects/<SHA>

# Upload same object again
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-dup.txt http://localhost/objects/<SHA>
```

### Expected

- Both uploads succeed with HTTP 200 OK
- Second upload is a no-op (object already exists with valid checksum)

---

## Test 17: Daemons List

**Endpoint**: `GET /daemons`

### Execute

```bash
./tools/testing/pva pvc http://localhost/daemons
```

### Expected

- JSON array of daemon objects
- Each daemon has: `name`, `pid`, `respawn`
- With xconnect enabled: `pv-xconnect` daemon present with `pid > 0` and `respawn: true`

---

## Test 18: Daemon Stop

**Endpoint**: `PUT /daemons/{name}` with `{"action":"stop"}`

### Execute

```bash
# Verify pv-xconnect is running
./tools/testing/pva exec ps aux

# Stop it
./tools/testing/pva pvc -X PUT --data '{"action":"stop"}' http://localhost/daemons/pv-xconnect

# Verify stopped
sleep 2
./tools/testing/pva exec ps aux
./tools/testing/pva pvc http://localhost/daemons
```

### Expected

| Step | Expected |
|------|----------|
| Before stop | pv-xconnect process running |
| Stop response | HTTP 200 OK |
| After stop | No pv-xconnect process |
| API status | `respawn: false`, `pid` is 0 or negative |

---

## Test 19: Daemon Start

**Endpoint**: `PUT /daemons/{name}` with `{"action":"start"}`

### Execute

```bash
# Start pv-xconnect (after Test 18 stopped it)
./tools/testing/pva pvc -X PUT --data '{"action":"start"}' http://localhost/daemons/pv-xconnect

# Verify running
sleep 2
./tools/testing/pva exec ps aux
./tools/testing/pva pvc http://localhost/daemons
```

### Expected

| Step | Expected |
|------|----------|
| Start response | HTTP 200 OK |
| After start | pv-xconnect process running again |
| API status | `respawn: true`, `pid > 0` |

---

## Test 20: Daemon Stop/Start - Non-Existent Daemon

**Endpoint**: `PUT /daemons/{name}`

### Execute

```bash
./tools/testing/pva pvc -X PUT --data '{"action":"stop"}' http://localhost/daemons/nonexistent-daemon
```

### Expected

- HTTP 404 NOT FOUND with "Daemon not found" error

---

## Test 21: XConnect Graph

**Endpoint**: `GET /xconnect-graph`

### Execute

```bash
./tools/testing/pva pvc http://localhost/xconnect-graph
```

### Expected

- JSON structure describing the service mesh graph
- With unix examples loaded: shows `unix` type link between server and client
- Contains provider and consumer information

---

## Test 22: Drivers List

**Endpoint**: `GET /drivers`

### Execute

```bash
./tools/testing/pva pvc http://localhost/drivers
```

### Expected

- JSON showing driver state for the caller's platform
- May be empty in appengine without platform containers that manage drivers

---

## Test 23: Drivers Load/Unload

**Endpoints**: `PUT /drivers/load`, `PUT /drivers/unload`

### Execute

```bash
# Load all drivers
./tools/testing/pva pvc -X PUT http://localhost/drivers/load

# Unload all drivers
./tools/testing/pva pvc -X PUT http://localhost/drivers/unload
```

### Expected

- Both return HTTP 200 OK (even if no drivers to load/unload)
- In appengine without hardware, these are effectively no-ops

---

## Test 24: Signal - Ready

**Endpoint**: `POST /signal`

### Execute

```bash
./tools/testing/pva pvc -X POST --data '{"type":"ready","payload":""}' http://localhost/signal
```

### Expected

- HTTP 500 "Signal not expected from this platform" when called from management socket
- Signals are designed for container sockets, not the management socket

---

## Test 25: Signal - Alive

**Endpoint**: `POST /signal`

### Execute

```bash
./tools/testing/pva pvc -X POST --data '{"type":"alive","payload":""}' http://localhost/signal
```

### Expected

- HTTP 500 "Signal not expected from this platform" (same as Test 24)

---

## Test 26: Commands - Poweroff

**Endpoint**: `POST /commands`

**WARNING**: This will shut down the appengine. Run last or skip in automated testing.

### Execute

```bash
./tools/testing/pva pvc -X POST --data '{"op":"POWEROFF_DEVICE","payload":"test shutdown"}' http://localhost/commands
```

### Expected

- HTTP 200 OK
- Pantavisor begins graceful shutdown sequence
- All containers are stopped before powering off

---

## Test 27: Commands - Run GC

**Endpoint**: `POST /commands`

### Execute

```bash
./tools/testing/pva pvc -X POST --data '{"op":"RUN_GC","payload":""}' http://localhost/commands
```

### Expected

- HTTP 200 OK or 503 SERVICE UNAVAILABLE (with Retry-After)
- Garbage collector runs, removing unused objects from storage

---

## Test 28: Container Start/Stop/Restart

**Note**: The `/containers/{name}` PUT endpoint is not implemented. Container lifecycle
is managed by pantavisor internally via revision transitions.

### Execute

```bash
./tools/testing/pva exec lxc-ls -f
```

### Expected

- N/A — endpoint not implemented

---

## Test 29: Steps Install (Local Revision)

**Endpoint**: `PUT /steps/locals/{name}`

### Execute

```bash
# Create a tarball (simplified - in real use this would be a valid pvrexport)
./tools/testing/pva exec sh -c 'cd /tmp && mkdir -p test-step && echo "{}" > test-step/state.json && tar czf test-step.tgz -C test-step .'

# Install as local revision
./tools/testing/pva pvc -X PUT -H "Content-Type: application/octet-stream" -T /tmp/test-step.tgz http://localhost/steps/locals/test-rev
```

### Expected

- HTTP 422 "Parser: State JSON has bad format" (needs valid state.json, not empty `{}`)
- With a valid pvrexport: HTTP 200 OK, new local revision created

---

## Test 30: Steps Put State JSON

**Endpoint**: `PUT /steps/locals/{name}`

### Execute

```bash
# Get current state
./tools/testing/pva pvc -o /tmp/state.json http://localhost/steps/current

# Put it as a new local revision
./tools/testing/pva pvc -X PUT -T /tmp/state.json http://localhost/steps/locals/test-put-rev

# Set commit message
./tools/testing/pva pvc -X PUT --data "test put commit" http://localhost/steps/locals/test-put-rev/commitmsg

# Verify
./tools/testing/pva pvc http://localhost/steps
```

### Expected

- HTTP 200 OK if state.json is valid
- New local revision visible in steps listing
- Commit message recorded

---

## Test 31: Commands - Enable/Disable SSH

**Endpoint**: `POST /commands`

### Execute

```bash
# Enable SSH
./tools/testing/pva pvc -X POST --data '{"op":"ENABLE_SSH","payload":""}' http://localhost/commands

# Wait for command to complete
sleep 2

# Disable SSH
./tools/testing/pva pvc -X POST --data '{"op":"DISABLE_SSH","payload":""}' http://localhost/commands
```

### Expected

- HTTP 200 OK for both commands
- SSH server state toggled (temporary, until reboot)

---

---

## Quick Reference: All Endpoints

| Endpoint | Methods | Mgmt | pva command |
|----------|---------|------|-------------|
| `/buildinfo` | GET | yes | `./tools/testing/pva exec pvcontrol buildinfo` |
| `/containers` | GET | yes | `./tools/testing/pva pvc http://localhost/containers` |
| `/groups` | GET | yes | `./tools/testing/pva pvc http://localhost/groups` |
| `/steps` | GET | yes | `./tools/testing/pva pvc http://localhost/steps` |
| `/steps/{name}` | GET | yes | `./tools/testing/pva pvc http://localhost/steps/<rev>` |
| `/steps/locals/{name}` | GET, PUT | yes | `./tools/testing/pva pvc -X PUT -T <file> http://localhost/steps/locals/<rev>` |
| `/steps/{name}/progress` | GET | yes | `./tools/testing/pva pvc http://localhost/steps/<rev>/progress` |
| `/steps/{name}/commitmsg` | PUT | yes | `./tools/testing/pva pvc -X PUT --data "<msg>" http://localhost/steps/<rev>/commitmsg` |
| `/config` | GET | yes | `./tools/testing/pva pvc http://localhost/config` |
| `/config2` | GET | yes | `./tools/testing/pva pvc http://localhost/config2` |
| `/device-meta` | GET | yes | `./tools/testing/pva pvc http://localhost/device-meta` |
| `/device-meta/{key}` | PUT, DELETE | yes | `./tools/testing/pva pvc -X PUT --data "<val>" http://localhost/device-meta/<key>` |
| `/user-meta` | GET | yes | `./tools/testing/pva pvc http://localhost/user-meta` |
| `/user-meta/{key}` | PUT, DELETE | yes | `./tools/testing/pva pvc -X PUT --data "<val>" http://localhost/user-meta/<key>` |
| `/objects` | GET | yes | `./tools/testing/pva pvc http://localhost/objects` |
| `/objects/{hash}` | GET, PUT | yes | `./tools/testing/pva pvc -X PUT -T <file> http://localhost/objects/<sha>` |
| `/drivers` | GET | yes | `./tools/testing/pva pvc http://localhost/drivers` |
| `/drivers/load` | PUT | yes | `./tools/testing/pva pvc -X PUT http://localhost/drivers/load` |
| `/drivers/unload` | PUT | yes | `./tools/testing/pva pvc -X PUT http://localhost/drivers/unload` |
| `/daemons` | GET | yes | `./tools/testing/pva pvc http://localhost/daemons` |
| `/daemons/{name}` | PUT | yes | `./tools/testing/pva pvc -X PUT --data '{"action":"..."}' http://localhost/daemons/<name>` |
| `/signal` | POST | **no** | `./tools/testing/pva pvc -X POST --data '{"type":"..."}' http://localhost/signal` |
| `/commands` | POST | yes | `./tools/testing/pva pvc -X POST --data '{"op":"..."}' http://localhost/commands` |
| `/xconnect-graph` | GET | yes | `./tools/testing/pva pvc http://localhost/xconnect-graph` |

---

## Validated Results (2026-02-26)

Tests executed against appengine with workspace overlay (pantavisor feature/xconnect-landing).

| Test | Status | Notes |
|------|--------|-------|
| Test 1: Build Info | PASS | Returns empty in appengine (expected) |
| Test 2: Containers List | PASS | Shows unix-server and unix-client |
| Test 3: Groups List | PASS | Shows data, root, platform, app groups |
| Test 4: Steps List | PASS | Shows revision 0 |
| Test 5: Steps Get | PASS | Returns full state.json |
| Test 6: Steps Progress | PASS | Returns progress with status |
| Test 7: Configuration | PASS | Both /config and /config2 return config |
| Test 8: Device Meta CRUD | PASS | Save, update, delete all work |
| Test 9: User Meta CRUD | PASS | Save, update, delete all work |
| Test 10: Delete Non-Existent | PASS | Returns 404 NOT FOUND |
| Test 11: Objects List | PASS | Returns SHA256 hash list |
| Test 12: Objects PUT Small | PASS | 24-byte file uploaded |
| Test 13: Objects PUT Large | PASS | 2MB file with chunked upload |
| Test 14: Objects GET + Verify | PASS | 2MB download, SHA256 checksum matches |
| Test 15: Objects Bad Hash | PASS | Returns 422, bad checksum rejected |
| Test 16: Objects Duplicate | PASS | Idempotent, both uploads succeed |
| Test 17: Daemons List | PASS | Shows pv-xconnect with PID |
| Test 18: Daemon Stop | PASS | pv-xconnect stops, respawn disabled |
| Test 19: Daemon Start | PASS | pv-xconnect restarts, respawn enabled |
| Test 20: Non-Existent Daemon | PASS | Returns 404 "Daemon not found" |
| Test 21: XConnect Graph | PASS | Shows unix link between containers |
| Test 22: Drivers List | PASS | Returns `{}` (no BSP/drivers in appengine) |
| Test 23: Drivers Load/Unload | PASS | Returns 200 OK (no-op without drivers) |
| Test 24: Signal Ready | EXPECTED | 500 "Signal not expected" - signals are container-only |
| Test 25: Signal Alive | EXPECTED | 500 "Signal not expected" - same as T24 |
| Test 26: Poweroff | SKIP | Destructive - shuts down appengine |
| Test 27: Run GC | PASS | Garbage collector runs successfully |
| Test 28: Container Stop/Start | N/A | `/containers/{name}` PUT endpoint not implemented |
| Test 29: Steps Install | EXPECTED | Needs valid pvrexport tarball structure |
| Test 30: Steps Put State | PASS | New local revision created with commitmsg |
| Test 31: Enable/Disable SSH | PASS | Both commands succeed |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty response on PUT | pvcurl header stripping | Check response manually with `./tools/testing/pva pvc -i` |
| HTTP 403 Forbidden | Request not from mgmt socket | Use correct socket path |
| Objects PUT returns 422 | SHA256 mismatch | Recompute hash with `./tools/testing/pva exec sha256sum` |
| Daemon not found | Wrong daemon name | Check `./tools/testing/pva pvc http://localhost/daemons` for exact names |
| Steps install fails | Invalid state.json | Validate JSON structure matches revision format |
| pvtx.d not processed | Storage volume reused | `docker volume rm storage-test` |
| Command already in progress | Race between sequential commands | Add `sleep 2` between commands |
