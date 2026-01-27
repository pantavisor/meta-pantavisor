# meta-pantavisor

Yocto/OpenEmbedded layer for building Pantavisor-based embedded Linux systems with containerized workloads.

## Overview

This layer provides:
- **Pantavisor runtime** recipes for embedded devices
- **Appengine** Docker-based development/testing environment
- **Example containers** demonstrating pv-xconnect service mesh patterns
- **KAS configurations** for reproducible builds

## Documentation

| Document | Description |
|----------|-------------|
| [DEVELOPMENT.md](DEVELOPMENT.md) | Development workflow - building, testing, iterating on pantavisor and containers |
| [EXAMPLES.md](EXAMPLES.md) | Example containers for pv-xconnect service mesh (Unix, REST, D-Bus, DRM, Wayland) |
| [GEMINI.md](GEMINI.md) | Branch-specific implementation notes and upstream changes |

## Quick Reference

### Building

```bash
# Standard build (upstream sources)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

# Development build (with local pantavisor workspace)
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml

# Build specific target
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml --target <recipe>
```

### Testing with Appengine

```bash
# Load docker image
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar

# Run appengine (interactive mode)
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:1.0 -c "sleep infinity"

# Start pantavisor
docker exec pva-test sh -c 'pv-appengine &'

# Check status
docker exec pva-test lxc-ls -f
```

### Key Paths

| Path | Description |
|------|-------------|
| `build/workspace/sources/pantavisor/` | Pantavisor source (when using with-workspace.yaml) |
| `build/tmp-scarthgap/deploy/images/` | Build outputs (images, pvrexports) |
| `recipes-containers/pv-examples/` | Example container recipes |
| `recipes-pv/` | Core pantavisor recipes |
| `.github/configs/release/` | KAS machine configurations |

## Directory Structure

```
meta-pantavisor/
├── classes/                    # BitBake classes (container-pvrexport, image-pvrexport)
├── conf/                       # Layer and distro configuration
├── dynamic-layers/             # Conditional recipes for other layers
├── kas/                        # KAS configuration fragments
├── recipes-containers/         # Container recipes
│   └── pv-examples/           # Example containers for testing
├── recipes-pv/                 # Core pantavisor recipes
│   ├── images/                # Appengine and BSP images
│   ├── pantavisor/            # Pantavisor runtime
│   └── pvr/                   # PVR tool
├── recipes-devtools/           # Development tools (pvcontrol, etc.)
└── recipes-wasm/              # WebAssembly runtime (wasmedge)
```

## Example Containers

The `pv-examples` containers demonstrate pv-xconnect service mesh patterns:

| Container | Type | Role | Description |
|-----------|------|------|-------------|
| `pv-example-unix-server` | unix | provider | Raw Unix socket server |
| `pv-example-unix-client` | unix | consumer | Raw Unix socket client |
| `pv-example-rest-server` | rest | provider | HTTP-over-UDS server |
| `pv-example-rest-client` | rest | consumer | HTTP-over-UDS client |
| `pv-example-dbus-server` | dbus | provider | D-Bus service |
| `pv-example-dbus-client` | dbus | consumer | D-Bus client |
| `pv-example-drm-provider` | drm | provider | DRM device exporter |
| `pv-example-drm-master` | drm | consumer | DRM master (KMS) |
| `pv-example-drm-render` | drm | consumer | DRM render node |
| `pv-example-wayland-server` | wayland | provider | Weston compositor |
| `pv-example-wayland-client` | wayland | consumer | Wayland client |

See [EXAMPLES.md](EXAMPLES.md) for detailed testing instructions.

## Pantavisor Source Development

When using `kas/with-workspace.yaml`, pantavisor source is available at:
```
build/workspace/sources/pantavisor/
```

Key pantavisor components:
- `xconnect/` - Service mesh daemon and plugins
- `ctrl/` - REST API control server
- `parser/` - State JSON parsing
- `plugins/` - Container runtime plugins (LXC, etc.)

See `build/workspace/sources/pantavisor/CLAUDE.md` for detailed pantavisor architecture.

## pv-xconnect Service Mesh

pv-xconnect mediates container-to-container communication:

- **Unix sockets**: Raw socket proxy with namespace injection
- **REST**: HTTP-over-UDS with identity headers (X-PV-Client, X-PV-Role)
- **D-Bus**: Policy-aware proxy with interface filtering
- **DRM**: Device node injection for graphics (card0, renderD128)
- **Wayland**: Compositor access for isolated UI rendering

Configuration:
- **Provider**: `services.json` declares exported services
- **Consumer**: `args.json` with `PV_SERVICES_REQUIRED`/`PV_SERVICES_OPTIONAL`

See `build/workspace/sources/pantavisor/xconnect/XCONNECT.md` for protocol specification.

## Common Tasks

### Add a new example container

1. Create recipe in `recipes-containers/pv-examples/`
2. Add `services.json` (provider) or `args.json` (consumer) in `files/`
3. Build with `--target pv-example-<name>`

### Test xconnect changes

1. Edit `build/workspace/sources/pantavisor/xconnect/`
2. Rebuild with `:kas/with-workspace.yaml`
3. Load new docker image and test with appengine

### Debug container issues

```bash
# Check pantavisor logs
docker exec pva-test cat /run/pantavisor/pv/logs/0/pantavisor/pantavisor.log

# Check container logs
docker exec pva-test cat /run/pantavisor/pv/logs/0/<container>/lxc/console.log

# Enter container namespace
docker exec -it pva-test pventer -c <container>

# Query xconnect graph
docker exec pva-test curl -s --max-time 3 \
    --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/xconnect-graph | jq .
```

## External Resources

- [Pantavisor Documentation](https://docs.pantahub.com/pantavisor-architecture/)
- [Pantahub Community](https://community.pantavisor.io)
- [Getting Started Guide](https://docs.pantahub.com/before-you-begin/)
