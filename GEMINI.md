# feature/wasmedge-engine

This branch adds support for the WasmEdge WebAssembly runtime as an engine for Pantavisor.

## Yocto Implementation Details

- **Recipe**: `recipes-wasm/wasmedge/wasmedge_git.bb`
  - Version: 0.14.1
  - Dependencies: `clang`, `libxml2`, `ncurses`, `spdlog`.
- **Kconfig integration**: 
  - `FEATURE_WASMEDGE`: Boolean to toggle the feature.
  - `FEATURE_XCONNECT`: Boolean to toggle `pv-xconnect` service.
- **Architecture Constraints**:
  - Automatically removed for `armv7ve` machines due to build failures in `wasmedge`.
- **KAS configuration**:
  - `kas/bsp-base.yaml` and `kas/appengine-base.yaml` add `meta-clang` repository.
  - LLVM preferred providers are set to `clang` in `conf/distro/panta-distro.inc`.

## Working with this branch

When making changes to Kconfig or features:
1. Update `Kconfig`.
2. Update `kas/bsp-base.yaml` if necessary.
3. Run `.github/scripts/makemachines` to regenerate release configurations.

**pvr workspace**: If you are using a custom `pvr` in the workspace, ensure `PVR_DISABLE_SELF_UPGRADE=1` is set to prevent auto-updates from overwriting it.

## Appengine Workflow

### Build and Load
1. Build the Appengine image:
   ```bash
   bitbake pantavisor-appengine
   ```
2. Build specific recipes or containers:
   - **Standard build**:
     ```bash
     ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml --target <recipename>
     ```
   - **Upstream development (with workspace)**:
     ```bash
     ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml --target <recipename>
     ```
3. Load the resulting Docker tarball:
   ```bash
   docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
   ```

### Run and Test

#### Quick Start (Auto Mode)
Start with default entrypoint (pv-appengine starts automatically):
```bash
docker run --name pva-test -d --privileged \
  -v /path/to/pvrexports:/usr/lib/pantavisor/pvtx.d \
  -v storage-test:/var/pantavisor/storage \
  pantavisor-appengine:1.0
```

#### Interactive Mode (Manual Control)
For debugging, use `sleep infinity` to keep container alive and control startup manually:
```bash
docker run --name pva-test -d --privileged \
  -v /path/to/pvrexports:/usr/lib/pantavisor/pvtx.d \
  -v storage-test:/var/pantavisor/storage \
  --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

# Then start pv-appengine manually
docker exec pva-test sh -c 'pv-appengine &'
```

#### Verify Pantavisor is Stable
**Important**: Always verify pantavisor has fully started before testing:
```bash
# Wait for READY status in logs
docker exec pva-test grep "status is now READY" /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log

# Expected output:
# [pantavisor] ... [state]: (pv_state_set_status:538) state revision '0' status is now READY
```

#### Check Container Status
```bash
docker exec pva-test lxc-ls -f
```

### Testing pv-ctrl API

Always use timeouts when testing APIs to catch hangs. Pantavisor now includes `pvcurl` (a lightweight curl wrapper using `nc`) which is preferred over standard `curl`:
```bash
# List all daemons
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons

# Stop a daemon (e.g. pv-xconnect)
docker exec pva-test pvcurl -X PUT --data '{"action":"stop"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect

# Start a daemon
docker exec pva-test pvcurl -X PUT --data '{"action":"start"}' --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons/pv-xconnect
```

**New Endpoint: /daemons**
- `GET /daemons`: Returns a JSON list of managed daemons, their PIDs and respawn status.
- `PUT /daemons/{name}`: Performs actions on a daemon.
  - `{"action": "stop"}`: Disables respawn and kills the daemon.
  - `{"action": "start"}`: Enables respawn and starts the daemon if not running.

**New Endpoint: /containers (Control)**
- `GET /containers`: Returns a JSON list of containers with their status.
- `PUT /containers/{name}`: Performs lifecycle actions on a container.
  - `{"action": "stop"}`: Stops the container and disables auto-recovery.
  - `{"action": "start"}`: Starts a stopped container.
  - `{"action": "restart"}`: Restarts the container (stop + start).

**Note:** Only containers with `restart_policy: "container"` can be controlled. Containers with `restart_policy: "system"` are protected and cannot be stopped/started via API.

**Container Control via pvcurl:**
```bash
# List containers with status
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers

# Stop a container
docker exec pva-test pvcurl -X PUT --data '{"action":"stop"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/pv-example-recovery

# Start a container
docker exec pva-test pvcurl -X PUT --data '{"action":"start"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/pv-example-recovery

# Restart a container
docker exec pva-test pvcurl -X PUT --data '{"action":"restart"}' \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers/pv-example-recovery
```

**Container Control via pvcontrol CLI:**
```bash
# List containers
docker exec pva-test pvcontrol container ls

# Stop a container
docker exec pva-test pvcontrol container stop pv-example-recovery

# Start a container
docker exec pva-test pvcontrol container start pv-example-recovery

# Restart a container
docker exec pva-test pvcontrol container restart pv-example-recovery
```

### Testing pv-xconnect Service Mesh

#### Understanding the xconnect-graph API

The xconnect-graph endpoint returns the current service mesh topology as JSON:
```bash
# Query the graph (always use timeout)
docker exec pva-test curl -s --max-time 3 --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph
```

**Expected response** (example with unix client/server):
```json
[{
  "type": "unix",
  "name": "raw",
  "consumer": "pv-example-unix-client",
  "role": "client",
  "socket": "/run/example/raw.sock",
  "interface": "/run/pv/services/raw.sock",
  "consumer_pid": 1234,
  "provider_pid": 5678
}]
```

**Fields:**
- `type`: Connection type (unix, rest, drm, wayland)
- `name`: Service name from services.json/args.json
- `consumer`: Container requesting the service
- `role`: "client" or "server"
- `socket`: Provider's socket path (inside provider namespace)
- `interface`: Consumer's target socket path (where to inject proxy)
- `consumer_pid`: PID of the consumer container's init process
- `provider_pid`: PID of the provider container's init process

#### Running pv-xconnect Manually

Use `stdbuf` to see unbuffered output:
```bash
docker exec pva-test stdbuf -oL timeout 5 /usr/bin/pv-xconnect 2>&1
```

**Expected output when working correctly:**
```
pv-xconnect starting...
Connected to pv-ctrl
Reconciling graph with 1 links
Adding link: pv-example-unix-client (pid=1234, unix) -> /run/example/raw.sock (inject to: /run/pv/services/raw.sock)
pvx-unix: Injecting socket /run/pv/services/raw.sock into pid 1234
```

**Note:** The PID will be the actual init PID of the consumer container.

#### Verifying Socket Injection

After pv-xconnect runs, check if the socket was injected into the consumer container:
```bash
# Get consumer container's PID
docker exec pva-test lxc-info -n pv-example-unix-client -p

# Check for injected socket (replace PID)
docker exec pva-test ls -la /proc/<PID>/root/run/pv/services/
```

### D-Bus Example Containers

The `pv-example-dbus-*` containers demonstrate cross-container D-Bus communication with Role-based identities.

- **`pv-example-dbus-server`**:
  - Runs a `dbus-daemon` and a Python service (`pv-dbus-server.py`).
  - Publishes the `org.pantavisor.Example` name.
  - Policy file allows `root` role to own the service and `nobody` role to send messages.
- **`pv-example-dbus-client`**:
  - Assigns the **`root`** role in `args.json`.
  - Maps to the provider's `root` user (UID 0) via `pv-xconnect`.
- **`pv-example-dbus-client-nobody`**:
  - Assigns the **`nobody`** role in `args.json`.
  - Maps to the provider's `nobody` user (UID 65534).

#### Running the D-Bus Test

1. **Build and Load**:
   ```bash
   ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
     --target pv-example-dbus-server --target pv-example-dbus-client --target pv-example-dbus-client-nobody
   ```
2. **Start Appengine** (see Quick Start above).
3. **Reconcile with pv-xconnect**:
   ```bash
   docker exec pva-test /usr/bin/pv-xconnect
   ```
4. **Observe Results**:
   - `pv-example-dbus-client` will successfully call the service as `root`.
   - `pv-example-dbus-client-nobody` will successfully call the service as `nobody`.
   - The provider logs will show separate connections for each role.

### Complete xconnect Test Workflow

1. **Start with fresh state:**
   ```bash
   docker rm -f pva-test
   docker volume rm storage-test
   ```

2. **Run appengine with test containers:**
   ```bash
   docker run --name pva-test -d --privileged \
     -v /path/to/pvtx.d:/usr/lib/pantavisor/pvtx.d \
     -v storage-test:/var/pantavisor/storage \
     --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"
   ```

3. **Start pv-appengine and wait for READY:**
   ```bash
   docker exec pva-test sh -c 'pv-appengine &'
   sleep 5
   docker exec pva-test grep "status is now READY" /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log
   ```

4. **Verify containers are running:**
   ```bash
   docker exec pva-test lxc-ls -f
   ```

5. **Test the xconnect-graph API:**
   ```bash
   docker exec pva-test curl -s --max-time 3 --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
   ```

6. **Run pv-xconnect and observe:**
   ```bash
   docker exec pva-test stdbuf -oL timeout 10 /usr/bin/pv-xconnect 2>&1
   ```

7. **Verify API still works after pv-xconnect (DoS regression test):**
   ```bash
   docker exec pva-test curl -s --max-time 3 --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers
   ```

### xconnect Test Container Setup

The pv-examples containers demonstrate xconnect service mesh patterns.

#### Provider Container (e.g., pv-example-unix-server)

Creates a `services.json` declaring exported services:
```json
{
  "services": [
    {
      "type": "unix",
      "name": "raw",
      "socket": "/run/example/raw.sock"
    }
  ]
}
```

#### Consumer Container (e.g., pv-example-unix-client)

Creates an `args.json` with service requirements that get rendered into `run.json`:
```json
{
  "services": [
    {
      "type": "unix",
      "name": "raw",
      "provider": "pv-example-unix-server",
      "socket": "/run/pv/services/raw.sock"
    }
  ]
}
```

The `socket` field in args.json specifies where pv-xconnect should inject the proxied socket inside the consumer's namespace.

**Note:** pvr transforms args.json into run.json with "target" as the field name (instead of "socket"). The parser accepts both "interface" and "target" as aliases.

#### How xconnect Accesses Container Namespaces

pv-xconnect uses `/proc/{pid}/root/` paths to access container filesystems:

- **Provider socket**: Accessed via `/proc/{provider_pid}/root{socket_path}`
- **Consumer socket**: Injected using `setns()` into the consumer's mount namespace

This allows the xconnect proxy to bridge containers without requiring shared mounts.

#### Building Test Containers

```bash
# Build the example containers with workspace (for upstream pantavisor changes)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
  --target pv-example-unix-server --target pv-example-unix-client
```

The pvrexport outputs will be in:
- `build/tmp-scarthgap/deploy/pvrexports/pv-example-unix-server/`
- `build/tmp-scarthgap/deploy/pvrexports/pv-example-unix-client/`

### Inspection and Debugging

#### Check LXC Containers
```bash
docker exec pva-test lxc-ls -f
```

#### Enter a Container
```bash
docker exec -it pva-test pventer -c <container_name>
```

#### Check Inside Container's Namespace
```bash
# Get container PID
docker exec pva-test lxc-info -n <container_name> -p

# Check files in container's rootfs (replace PID)
docker exec pva-test ls -la /proc/<PID>/root/run/pv/services/
```

#### Log Locations
- **Pantavisor**: `/run/pantavisor/pv/logs/0/pantavisor/pantavisor.log`
- **Container Console**: `/run/pantavisor/pv/logs/0/<container_name>/lxc/console.log`
- **LXC Log**: `/run/pantavisor/pv/logs/0/<container_name>/lxc/lxc.log`

### Cleanup Between Tests

Use fresh storage volumes to avoid stale state:
```bash
docker rm -f pva-test
docker volume rm storage-test
# Then start fresh
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| API calls hang/timeout | Missing Host header in client | Ensure HTTP requests include `Host: localhost` header |
| Container crashes on pv-xconnect start | Bad storage state | Use fresh storage volume |
| "Socket not found" in client | pv-xconnect not injecting socket | Check pv-xconnect output with `stdbuf -oL` |
| No output from pv-xconnect | stdout buffering | Use `stdbuf -oL` prefix |
| `interface: null` in xconnect-graph | Parser not finding target field | Ensure parser accepts "target" as alias for "interface" |
| `consumer_pid: 0` | PID not being parsed | Ensure main.c parses consumer_pid from JSON |
| "Could not connect to provider socket" | Wrong namespace path | Use `/proc/{pid}/root/` to access container filesystem |
| "Broken pipe" errors | Proxy closing too early | Ensure half-close handling in unix.c proxy |

## Upstream Pantavisor Changes

Key changes made in pantavisor workspace (`build/workspace/sources/pantavisor`) for xconnect:

### ctrl/ctrl.c - Host Header DoS Fix
- Fixed vulnerability where NULL/empty Host header caused server hang
- Now allows localhost, empty, or NULL host for Unix socket connections

### xconnect/main.c - JSON Parsing
- Added parsing of `consumer_pid`, `provider_pid`, `interface` fields
- Uses `interface` as consumer socket path for injection target

### parser/parser_system1.c - Target Alias
- Parser now accepts "target" as alias for "interface"
- Needed because pvr renders args.json "socket" field as "target" in run.json

### xconnect/plugins/unix.c - Namespace and Proxy Fixes
- Provider socket access via `/proc/{pid}/root/` path
- Proper half-close session tracking for bidirectional communication
- Fixes "broken pipe" errors when provider sends response

## Architecture

For the design of the service mesh and `pv-xconnect`, please refer to the documentation in the `pantavisor` source repository:
- `GEMINI.md`: High-level vision.
- `xconnect/XCONNECT.md`: Detailed `pv-xconnect` implementation notes.

## Checkpoint (2026-01-22)

### Achieved so far
1. **Auto-Recovery Feature:**
    * **Status:** Core logic verified and functional.
    * **Parsing:** Pantavisor correctly parses `PV_AUTO_RECOVERY` from `run.json` (max_retries, retry_delay, backoff_factor, reset_window).
    * **State Engine:** Exponential backoff and recovery state transitions verified using `pv-example-random`.
    * **Examples:** Created `pv-example-random` which uses `$RANDOM` for jittered crashes. Fixed Yocto recipes to correctly install scripts via `ROOTFS_POSTPROCESS_COMMAND`.
2. **pv-xconnect / DRM Service Mesh:**
    * **Device Injection:** Implemented `pvx_helper_inject_devnode` in `pv-xconnect` using `mknod` to inject device nodes into consumer mount namespaces.
    * **API Robustness:** Fixed a bug in Pantavisor's cgroup parsing that caused `xconnect-graph` to return "Internal Error" in Appengine mode (now correctly identifies `_pv_` privileged callers).
    * **Restart Policies:** Updated example DRM containers to use `container` restart policy, preventing system-wide reboots on local device timeouts.
3. **Build Infrastructure:**
    * **libthttp Integration:** Linked `libthttp` to the workspace via `libthttp_git.bbappend` to enable local iterative development of JSMN utilities.
    * **JSMN Utilities:** Exported `jsmnutil_traverse_token` from `libthttp` to allow `pv-xconnect` to accurately calculate object sizes during graph reconciliation.
4. **Container Control API:**
    * **REST API:** Added `PUT /containers/{name}` endpoint with start/stop/restart actions.
    * **pvcontrol CLI:** Added `pvcontrol container <ls|start|stop|restart>` commands.
    * **Safety:** Only containers with `restart_policy: "container"` can be controlled; system containers are protected.
    * **Auto-recovery Integration:** Explicit stop via API disables auto-recovery to prevent immediate restart loops.

### Current Blockers
- **Build Issue:** `pv-xconnect` currently failing to link against `libthttp` due to `jsmnutil_traverse_token` visibility/linking issues despite header exports.

### Next Steps
1. **Fix Linking:** Resolve the `jsmnutil_traverse_token` undefined reference in `pv-xconnect`.
2. **Verify DRM:** Once build is fixed, confirm `/dev/dri/card0` injection into `pv-example-drm-master`.
3. **Upstream PRs:** Finalize commits in `pantavisor` and `libthttp` workspaces.
