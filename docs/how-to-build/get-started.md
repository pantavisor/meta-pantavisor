# Get Started

## Prerequisites

- Docker installed and running
- Git configured
- ~50 GB free disk space for builds

## Repository Setup

```bash
git clone https://github.com/pantavisor/meta-pantavisor.git
cd meta-pantavisor
```

## Build Modes

### Standard Build (release sources)

Builds using upstream pinned sources. Suitable for producing release artifacts.

```bash
# Interactive configuration menu
kas menu Kconfig

# Build from generated .config.yaml
kas build .config.yaml

# Or build directly with a release config
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml
```

### Workspace Build (local source development)

Adds `kas/with-workspace.yaml` to create a devtool workspace with editable pantavisor source. See [pantavisor-development.md](pantavisor-development.md).

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml
```

**Note on pvr**: When using a custom pvr binary from the workspace, auto-updates are disabled by setting `PVR_DISABLE_SELF_UPGRADE=1`. This is handled automatically by `container-pvrexport.bbclass`.

## Common Build Targets

| Target | Description |
|--------|-------------|
| `pantavisor-bsp` | Full BSP image with Pantavisor initramfs |
| `pantavisor-initramfs` | Standalone initramfs |
| `pantavisor-remix` | BSP with root container support |
| `pantavisor-starter` | Minimal starter image |
| `pantavisor-appengine` | Docker-based appengine image |

Build a specific target:
```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml --target pantavisor-appengine
```

## Direct BitBake (for integrators)

If you include meta-pantavisor in your own Yocto project without KAS:

```bash
source layers/poky/oe-init-build-env build
bitbake pantavisor-bsp
```

## KAS vs BitBake Command Reference

| Task | KAS (recommended) | BitBake (integrators) |
|------|-------------------|-----------------------|
| Build image | `kas build <config.yaml>` | `bitbake pantavisor-bsp` |
| Build specific target | `kas build <config.yaml> --target <recipe>` | `bitbake <recipe>` |
| Clean recipe | `kas shell <config.yaml> -c "bitbake -c clean <recipe>"` | `bitbake -c clean <recipe>` |
| Clean sstate | `kas shell <config.yaml> -c "bitbake -c cleansstate <recipe>"` | `bitbake -c cleansstate <recipe>` |
| Force rebuild | `kas shell <config.yaml> -c "bitbake -c compile -f <recipe>"` | `bitbake -c compile -f <recipe>` |
| devshell | `kas shell <config.yaml> -c "bitbake -c devshell <recipe>"` | `bitbake -c devshell <recipe>` |
| Interactive shell | `kas shell <config.yaml>` | `source oe-init-build-env` |

## Testing the Build

After building the appengine image, see [../testing/appengine-testing.md](../testing/appengine-testing.md) for the full test workflow.

Quick smoke test:
```bash
docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
docker rm -f pva-test 2>/dev/null; docker volume rm storage-test 2>/dev/null
docker run --name pva-test -d --privileged \
    -v $(pwd)/pvtx.d:/usr/lib/pantavisor/pvtx.d \
    -v storage-test:/var/pantavisor/storage \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
docker exec pva-test sh -c 'pv-appengine &'
sleep 25
docker exec pva-test pvcurl --unix-socket /run/pantavisor/pv/pv-ctrl http://localhost/buildinfo
docker exec pva-test lxc-ls -f
```

**Important**: When testing new containers or changes to pvtx.d:
- Delete the storage volume to retrigger pvtx.d processing: `docker volume rm storage-test`
- Or remove the marker: `docker exec pva-test rm /var/pantavisor/storage/.pvtx-done`
- pvtx.d scripts only run once per storage volume (when `.pvtx-done` is absent)
