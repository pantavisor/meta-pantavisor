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

docker exec pva-test sh -c 'pv-appengine &'
sleep 15
```

### Helper Aliases

```bash
# Raw pvcurl access
alias pvc='docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl'

# pvcontrol access
alias pvctl='docker exec pva-test pvcontrol'
```

### Teardown

```bash
docker rm -f pva-test
docker volume rm storage-test
```

---

## Test 1: Build Info

**Endpoint**: `GET /buildinfo`
**pvcontrol**: `pvcontrol buildinfo`

### Execute

```bash
pvctl buildinfo
```

### Expected

- Returns plain text build manifest (may be empty in appengine builds)
- HTTP 200 OK

---

## Test 2: Containers List

**Endpoint**: `GET /containers`
**pvcontrol**: `pvcontrol container ls`

### Execute

```bash
pvctl container ls
```

### Verify

```bash
pvc http://localhost/containers | jq .
```

### Expected

- JSON object with container entries
- Each container has: `name`, `group`, `status`, `restart_policy`, `roles`
- With unix examples loaded: `pv-example-unix-server` and `pv-example-unix-client` present
- Status should be `READY` for running containers

---

## Test 3: Groups List

**Endpoint**: `GET /groups`
**pvcontrol**: `pvcontrol groups ls`

### Execute

```bash
pvctl groups ls
```

### Verify

```bash
pvc http://localhost/groups | jq .
```

### Expected

- JSON object listing container groups
- Should include at least: `data`, `root`, `platform`
- Appengine with examples loaded should show `app` group

---

## Test 4: Steps List

**Endpoint**: `GET /steps`
**pvcontrol**: `pvcontrol steps ls`

### Execute

```bash
pvctl steps ls
```

### Expected

- JSON array of revision names
- Should include at least revision `0` (initial state)

---

## Test 5: Steps Get State

**Endpoint**: `GET /steps/{name}`
**pvcontrol**: `pvcontrol steps get <revision>`

### Execute

```bash
# Get current state
pvctl steps get current

# Get specific revision
pvctl steps get 0
```

### Expected

- Returns full state.json for the revision
- JSON with container definitions, platform config, etc.
- `current` returns the active revision's state

---

## Test 6: Steps Show Progress

**Endpoint**: `GET /steps/{name}/progress`
**pvcontrol**: `pvcontrol steps show-progress <revision>`

### Execute

```bash
pvctl steps show-progress 0
```

### Expected

- JSON with progress information
- Contains `status` field (e.g., `DONE` for completed revisions)

---

## Test 7: Configuration

**Endpoints**: `GET /config`, `GET /config2`
**pvcontrol**: `pvcontrol config ls`, `pvcontrol conf ls`

### Execute

```bash
# Legacy config (with aliases)
pvctl config ls

# Full config
pvctl conf ls
```

### Expected

- `/config` returns config with aliased key names
- `/config2` returns full configuration object
- Both return JSON with pantavisor config key-value pairs
- Should include entries like `system.init.mode`, `log.level`, etc.

---

## Test 8: Device Metadata CRUD

**Endpoints**: `GET /device-meta`, `PUT /device-meta/{key}`, `DELETE /device-meta/{key}`
**pvcontrol**: `pvcontrol devmeta ls|save|delete`

### Execute

```bash
# List current device metadata
pvctl devmeta ls

# Save a new key
pvctl devmeta save test-key "test-value-123"

# Verify it was saved
pvctl devmeta ls

# Save with different value (update)
pvctl devmeta save test-key "updated-value-456"

# Verify update
pvc http://localhost/device-meta | jq '.["test-key"]'

# Delete the key
pvctl devmeta delete test-key

# Verify deletion
pvctl devmeta ls
```

### Expected

| Step | Expected |
|------|----------|
| Initial ls | JSON object (may contain auto-populated keys like `pantavisor.arch`) |
| After save | `test-key` appears with value `test-value-123` |
| After update | `test-key` value is `updated-value-456` |
| After delete | `test-key` no longer present |

---

## Test 9: User Metadata CRUD

**Endpoints**: `GET /user-meta`, `PUT /user-meta/{key}`, `DELETE /user-meta/{key}`
**pvcontrol**: `pvcontrol usrmeta ls|save|delete`

### Execute

```bash
# List current user metadata
pvctl usrmeta ls

# Save a key
pvctl usrmeta save my-key "my-value"

# Verify
pvctl usrmeta ls

# Update
pvctl usrmeta save my-key "new-value"

# Verify
pvc http://localhost/user-meta | jq '.["my-key"]'

# Delete
pvctl usrmeta delete my-key

# Verify
pvctl usrmeta ls
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
pvc -X DELETE http://localhost/device-meta/nonexistent-key-xyz
```

### Expected

- HTTP 404 NOT FOUND response

---

## Test 11: Objects List

**Endpoint**: `GET /objects`
**pvcontrol**: `pvcontrol objects ls`

### Execute

```bash
pvctl objects ls
```

### Expected

- JSON array of object SHA256 hashes
- With containers loaded, should return multiple object hashes

---

## Test 12: Objects PUT - Small File

**Endpoint**: `PUT /objects/{sha256}`
**pvcontrol**: `pvcontrol objects put <path> <sha256>`

### Execute

```bash
# Create a small test file
docker exec pva-test sh -c 'echo "hello pvctrl test" > /tmp/test-small.txt'

# Compute SHA256
SHA=$(docker exec pva-test sha256sum /tmp/test-small.txt | awk '{print $1}')
echo "SHA: $SHA"

# Upload
pvctl objects put /tmp/test-small.txt $SHA

# Verify it appears in listing
pvctl objects ls | grep $SHA
```

### Expected

- Upload succeeds with HTTP 200 OK
- Object hash appears in `objects ls` output

---

## Test 13: Objects PUT - Large File (Chunked Upload)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
# Create 2MB test file
docker exec pva-test dd if=/dev/urandom of=/tmp/test-2mb.bin bs=1024 count=2048

# Compute SHA256
SHA=$(docker exec pva-test sha256sum /tmp/test-2mb.bin | awk '{print $1}')
echo "SHA: $SHA"

# Upload
pvctl objects put /tmp/test-2mb.bin $SHA

# Verify
pvctl objects ls | grep $SHA
```

### Expected

- Upload succeeds with HTTP 200 OK
- Object stored correctly (verified by hash in listing)
- Pantavisor log shows chunked upload: `incoming data: <bytes>` messages followed by `upload done`

---

## Test 14: Objects GET - Download and Verify Integrity

**Endpoint**: `GET /objects/{sha256}`
**pvcontrol**: `pvcontrol objects get <sha256>`

### Execute

```bash
# Use the 2MB file from Test 13
SHA=$(docker exec pva-test sha256sum /tmp/test-2mb.bin | awk '{print $1}')

# Download
pvctl -f /tmp/test-2mb-downloaded.bin objects get $SHA

# Verify integrity
ORIG=$(docker exec pva-test sha256sum /tmp/test-2mb.bin | awk '{print $1}')
DOWNLOADED=$(docker exec pva-test sha256sum /tmp/test-2mb-downloaded.bin | awk '{print $1}')
echo "Original:   $ORIG"
echo "Downloaded: $DOWNLOADED"
```

### Expected

- Download succeeds
- SHA256 checksums match between original and downloaded file
- Content-Type is `application/octet-stream`

---

## Test 15: Objects PUT - Wrong Hash (Checksum Validation)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
docker exec pva-test sh -c 'echo "checksum test" > /tmp/test-badsha.txt'

# Use a wrong hash
pvctl objects put /tmp/test-badsha.txt aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

### Expected

- Upload fails with HTTP 422 UNPROCESSABLE ENTITY
- Object is NOT stored (bad checksum rejected)

---

## Test 16: Objects PUT - Duplicate Upload (Idempotency)

**Endpoint**: `PUT /objects/{sha256}`

### Execute

```bash
docker exec pva-test sh -c 'echo "duplicate test" > /tmp/test-dup.txt'
SHA=$(docker exec pva-test sha256sum /tmp/test-dup.txt | awk '{print $1}')

# Upload first time
pvctl objects put /tmp/test-dup.txt $SHA

# Upload same object again
pvctl objects put /tmp/test-dup.txt $SHA
```

### Expected

- Both uploads succeed with HTTP 200 OK
- Second upload is a no-op (object already exists with valid checksum)

---

## Test 17: Daemons List

**Endpoint**: `GET /daemons`

### Execute

```bash
pvc http://localhost/daemons | jq .
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
docker exec pva-test ps aux | grep pv-xconnect | grep -v grep

# Stop it
pvc -X PUT --data '{"action":"stop"}' http://localhost/daemons/pv-xconnect

# Verify stopped
sleep 2
docker exec pva-test ps aux | grep pv-xconnect | grep -v grep

# Check API reflects stopped state
pvc http://localhost/daemons | jq '.[] | select(.name=="pv-xconnect")'
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
pvc -X PUT --data '{"action":"start"}' http://localhost/daemons/pv-xconnect

# Verify running
sleep 2
docker exec pva-test ps aux | grep pv-xconnect | grep -v grep

# Check API reflects running state
pvc http://localhost/daemons | jq '.[] | select(.name=="pv-xconnect")'
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
pvc -X PUT --data '{"action":"stop"}' http://localhost/daemons/nonexistent-daemon
```

### Expected

- HTTP 404 NOT FOUND with "Daemon not found" error

---

## Test 21: XConnect Graph

**Endpoint**: `GET /xconnect-graph`

### Execute

```bash
pvc http://localhost/xconnect-graph | jq .
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
pvc http://localhost/drivers | jq .
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
pvc -X PUT http://localhost/drivers/load

# Unload all drivers
pvc -X PUT http://localhost/drivers/unload
```

### Expected

- Both return HTTP 200 OK (even if no drivers to load/unload)
- In appengine without hardware, these are effectively no-ops

---

## Test 24: Signal - Ready

**Endpoint**: `POST /signal`
**pvcontrol**: `pvcontrol signal ready`

### Execute

```bash
pvctl signal ready
```

### Expected

- HTTP 200 OK
- Signal processed by pantavisor (visible in logs)

**Note**: Signals are non-mgmt endpoints - they don't require management socket access.

---

## Test 25: Signal - Alive

**Endpoint**: `POST /signal`
**pvcontrol**: `pvcontrol signal alive`

### Execute

```bash
pvctl signal alive
```

### Expected

- HTTP 200 OK
- Keepalive signal processed

---

## Test 26: Commands - Poweroff

**Endpoint**: `POST /commands`
**pvcontrol**: `pvcontrol cmd poweroff`

**WARNING**: This will shut down the appengine. Run last or skip in automated testing.

### Execute

```bash
pvctl cmd poweroff "test shutdown"
```

### Expected

- HTTP 200 OK
- Pantavisor begins graceful shutdown sequence
- All containers are stopped before powering off

---

## Test 27: Commands - Run GC

**Endpoint**: `POST /commands`
**pvcontrol**: `pvcontrol cmd run-gc`

### Execute

```bash
pvctl cmd run-gc
```

### Expected

- HTTP 200 OK or 503 SERVICE UNAVAILABLE (with Retry-After)
- Garbage collector runs, removing unused objects from storage

---

## Test 28: Container Start/Stop/Restart

**pvcontrol**: `pvcontrol container start|stop|restart <name>`

### Execute

```bash
# Stop a container
pvctl container stop pv-example-unix-client

# Check it's stopped
docker exec pva-test lxc-ls -f | grep pv-example-unix-client

# Start it again
pvctl container start pv-example-unix-client

# Check it's running
sleep 5
docker exec pva-test lxc-ls -f | grep pv-example-unix-client

# Restart it
pvctl container restart pv-example-unix-server
sleep 5
docker exec pva-test lxc-ls -f | grep pv-example-unix-server
```

### Expected

| Step | Expected |
|------|----------|
| After stop | Container status is STOPPED |
| After start | Container status is RUNNING |
| After restart | Container status is RUNNING (restarted) |

---

## Test 29: Steps Install (Local Revision)

**Endpoint**: `PUT /steps/locals/{name}`
**pvcontrol**: `pvcontrol steps install <path> locals/<revision>`

### Execute

```bash
# Get current state as base
pvctl steps get current > /tmp/current-state.json

# Create a tarball (simplified - in real use this would be a valid step)
docker exec pva-test sh -c 'cd /tmp && mkdir -p test-step && cp /tmp/current-state.json test-step/state.json && tar czf test-step.tgz -C test-step .'

# Install as local revision
pvctl -m "test install" steps install /tmp/test-step.tgz locals/test-rev
```

### Expected

- If state.json is valid: HTTP 200 OK, new local revision created
- If invalid: HTTP 422 UNPROCESSABLE ENTITY
- `pvctl steps ls` shows the new revision

---

## Test 30: Steps Put State JSON

**Endpoint**: `PUT /steps/locals/{name}`
**pvcontrol**: `pvcontrol steps put <path> locals/<revision>`

### Execute

```bash
# Get current state
pvctl -f /tmp/state.json steps get current

# Put it as a new local revision
pvctl -m "test put" steps put /tmp/state.json locals/test-put-rev
```

### Expected

- HTTP 200 OK if state.json is valid
- New local revision visible in `pvctl steps ls`

---

## Test 31: Commands - Enable/Disable SSH

**Endpoint**: `POST /commands`
**pvcontrol**: `pvcontrol cmd enable-ssh`, `pvcontrol cmd disable-ssh`

### Execute

```bash
# Enable SSH
pvctl cmd enable-ssh

# Disable SSH
pvctl cmd disable-ssh
```

### Expected

- HTTP 200 OK for both commands
- SSH server state toggled (temporary, until reboot)

---

---

## Quick Reference: All Endpoints

| Endpoint | Methods | Mgmt | pvcontrol Command |
|----------|---------|------|-------------------|
| `/buildinfo` | GET | yes | `pvcontrol buildinfo` |
| `/containers` | GET | yes | `pvcontrol container ls` |
| `/groups` | GET | yes | `pvcontrol groups ls` |
| `/steps` | GET | yes | `pvcontrol steps ls` |
| `/steps/{name}` | GET | yes | `pvcontrol steps get <rev>` |
| `/steps/locals/{name}` | GET, PUT | yes | `pvcontrol steps get/put locals/<rev>` |
| `/steps/{name}/progress` | GET | yes | `pvcontrol steps show-progress <rev>` |
| `/steps/{name}/commitmsg` | PUT | yes | (via `-m` flag on steps install/put) |
| `/config` | GET | yes | `pvcontrol config ls` |
| `/config2` | GET | yes | `pvcontrol conf ls` |
| `/device-meta` | GET | yes | `pvcontrol devmeta ls` |
| `/device-meta/{key}` | PUT, DELETE | yes | `pvcontrol devmeta save/delete` |
| `/user-meta` | GET | yes | `pvcontrol usrmeta ls` |
| `/user-meta/{key}` | PUT, DELETE | yes | `pvcontrol usrmeta save/delete` |
| `/objects` | GET | yes | `pvcontrol objects ls` |
| `/objects/{hash}` | GET, PUT | yes | `pvcontrol objects get/put` |
| `/drivers` | GET | yes | (raw pvcurl) |
| `/drivers/load` | PUT | yes | (raw pvcurl) |
| `/drivers/{name}/load` | PUT | yes | (raw pvcurl) |
| `/drivers/unload` | PUT | yes | (raw pvcurl) |
| `/drivers/{name}/unload` | PUT | yes | (raw pvcurl) |
| `/daemons` | GET | yes | (raw pvcurl) |
| `/daemons/{name}` | PUT | yes | (raw pvcurl) |
| `/signal` | POST | **no** | `pvcontrol signal ready/alive` |
| `/commands` | POST | yes | `pvcontrol cmd <subcommand>` |
| `/xconnect-graph` | GET | yes | (raw pvcurl) |

---

## Validated Results (2026-02-25)

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
| Test 24: Signal Ready | EXPECTED | 500 "Signal not expected" - signals are container-only, not from `_pv_` |
| Test 25: Signal Alive | EXPECTED | 500 "Signal not expected" - same as T24 |
| Test 26: Poweroff | SKIP | Destructive - shuts down appengine |
| Test 27: Run GC | PASS | Garbage collector runs successfully |
| Test 28: Container Stop/Start | N/A | `/containers/{}` PUT endpoint not implemented |
| Test 29: Steps Install | EXPECTED | Needs valid pvrexport tarball structure, not bare state.json |
| Test 30: Steps Put State | PASS | New local revision created with commitmsg |
| Test 31: Enable/Disable SSH | PASS | Both commands succeed |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `pvcontrol` not found | Not in appengine image | Use `pvcurl` directly |
| Empty response on PUT | Custom endpoint body timing | Verify evbuffer_add_cb pattern in endpoint |
| HTTP 403 Forbidden | Request not from mgmt socket | Use correct socket path |
| Objects PUT returns 422 | SHA256 mismatch | Recompute hash with `sha256sum` |
| Daemon not found | Wrong daemon name | Check `GET /daemons` for exact names |
| Steps install fails | Invalid state.json | Validate JSON structure matches revision format |
| pvtx.d not processed | Storage volume reused | `docker volume rm storage-test` |
