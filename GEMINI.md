# feature/xconnect-landing

This branch adds pv-xconnect service mesh support, example containers, tooling, and appengine testing infrastructure.

## Branch Overview

All xconnect features are squashed into a single `feature/xconnect-landing` branch (both pantavisor and meta-pantavisor repos).

### Pantavisor Changes (SRCREV: 321480e767)

| Area | Key Changes |
|------|-------------|
| **xconnect/** | Service mesh daemon with plugins (unix, rest, dbus, drm, wayland) |
| **ctrl/** | REST API: /xconnect-graph, /daemons, /signal endpoints; NULL safety guards |
| **tools/** | pvcurl (lightweight curl via nc), pvcontrol (CLI wrapper) |
| **daemons** | Daemon stdout/stderr logging via logserver, /daemons stop/start API |
| **parser/** | `#spec: service-manifest-xconnect@1` format in services.json |
| **drivers** | NULL safety when no BSP/platform present (appengine mode) |

### Meta-pantavisor Changes

| Area | Key Changes |
|------|-------------|
| **recipes-containers/pv-examples/** | 25 example containers: unix, rest, dbus, drm, wayland, device-config |
| **classes/** | container-pvrexport.bbclass, image-pvrexport.bbclass |
| **conf/distro/** | panta-appengine.inc fix (`:append` instead of `+=` for PANTAVISOR_FEATURES) |
| **Kconfig** | FEATURE_XCONNECT toggle |
| **Documentation** | EXAMPLES.md, TESTPLANS.md, TESTPLAN-pvctrl.md, DEVELOPMENT.md |
| **Testing** | pva-test-runner agent, pva helper tool |

## Key Technical Details

### PANTAVISOR_FEATURES and the `+=` vs `:append` Pitfall

`pvbase.bbclass` sets defaults via `??=` (weak default):
```bitbake
PANTAVISOR_FEATURES ??= " dm-crypt dm-verity autogrow runc tailscale debug rngdaemon pvcontrol xconnect "
```

**Critical**: Distro includes must use `:append`/`:remove`, never `+=`:
```bitbake
# WRONG — clobbers ??= defaults, silently drops xconnect, pvcontrol, rngdaemon
PANTAVISOR_FEATURES += "appengine"

# CORRECT — preserves ??= defaults and appends
PANTAVISOR_FEATURES:append = " appengine"
```

This was fixed in `conf/distro/panta-appengine.inc` (commit 02cc695625).

### services.json Format

Providers declare services using the `#spec` format:
```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    {"name": "my-service", "type": "unix", "socket": "/run/my.sock"}
  ]
}
```

The `#spec` field is required for pantavisor's parser to identify and process the file.

### Consumer Service Requirements

Consumers declare requirements in `args.json`:
```json
{
  "PV_SERVICES_REQUIRED": "service1,service2",
  "PV_SERVICES_OPTIONAL": "service3"
}
```

pvr 047 templates (`builtin-lxc-docker.go`) transform these into `run.json` `services` section during `pvr app add`.

### pvcurl and pvcontrol

These are sub-packages of the pantavisor recipe (`pantavisor-pvcurl`, `pantavisor-pvcontrol`):
- **pvcurl**: Shell script wrapping `nc` for HTTP-over-Unix-socket. Supports `-X`, `-T` (timeout), `-v` (verbose), `-o` (output file), `-w` (response code), `--data`.
- **pvcontrol**: Shell script wrapping pvcurl for common pv-ctrl operations.

**Note**: The appengine image recipe does not include these sub-packages directly. They are available inside example container squashfs filesystems and in the initramfs when `pvcontrol` feature is enabled.

### Daemons API

- `GET /daemons` — List managed daemons with PID and respawn status
- `PUT /daemons/{name}` with `{"action":"stop"}` — Disable respawn and kill daemon
- `PUT /daemons/{name}` with `{"action":"start"}` — Enable respawn and start daemon

pv-xconnect runs as a managed daemon (registered with `DM_ALL` mode flag).

## Appengine Workflow

### Build and Load
```bash
# Standard build (uses upstream SRCREV)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

# With workspace (local pantavisor changes)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# Load docker image
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Run and Test
```bash
# Setup
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
mkdir -p pvtx.d && rm -f pvtx.d/*.pvrexport.tgz
cp build/tmp-scarthgap/deploy/images/docker-x86_64/*.pvrexport.tgz pvtx.d/

# Run (interactive mode)
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"

# Start and wait for ready
docker exec pva-test sh -c 'pv-appengine &'
sleep 25

# Verify
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/buildinfo
docker exec pva-test lxc-ls -f
```

### API Testing with pvcurl
```bash
# Inside container (preferred over curl)
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/containers
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/daemons
```

## Test Results (2026-02-27)

All 31 pv-ctrl API tests pass (TESTPLAN-pvctrl.md):
- Build info, containers, groups, steps, config: PASS
- Device/user metadata CRUD: PASS
- Objects (put/get/list/hash validation): PASS
- Daemons (list, stop, start, verify pv-xconnect): PASS
- xconnect-graph (query, verify links): PASS
- Signal endpoint: PASS

CI builds pass on all 3 targets: docker-x86_64, raspberrypi-armv8, sunxi-bananapi-m2-berry.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| xconnect/pvcontrol/rngdaemon missing from build | `+=` in distro include clobbers `??=` defaults | Use `:append` instead of `+=` for PANTAVISOR_FEATURES |
| `curl` not found in appengine | Standard curl not in image | Use `pvcurl` (shell wrapper using nc) |
| pvcurl/pvcontrol not in appengine image | Sub-packages not in image recipe | Copy from example container squashfs or add to image recipe |
| Container crashes on pv-xconnect start | Bad storage state | Use fresh storage volume (`docker volume rm storage-test`) |
| pvtx.d containers not loading | `.pvtx-done` marker exists | Remove marker or delete storage volume |
| `consumer_pid: 0` in xconnect-graph | Container not fully started | Wait for READY status before querying |

## Development Guidelines

- **Formatting**: Run `clang-format -i` on modified `.c`/`.h` files before committing pantavisor code
- **API testing**: Use `pvcurl` (not `curl`) inside appengine containers
- **Storage state**: Always use fresh storage volumes when testing pvtx.d changes
- **Kconfig changes**: Run `.github/scripts/makemachines` after modifying Kconfig
