# Container Development

## Creating Example Containers

Example containers live in `recipes-containers/pv-examples/`. Each container needs:

### 1. Recipe file (`pv-example-foo_1.0.bb`)

```bitbake
SUMMARY = "Example Foo Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-foo"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "busybox"

SRC_URI += "file://${PN}.services.json \
            file://${PN}.args.json"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/bin/sh"
```

### 2. `services.json` (providers)

Declares the services this container exports. The `#spec` versioning field is required:

```json
{
  "#spec": "service-manifest-xconnect@1",
  "services": [
    {"name": "my-service", "type": "unix", "socket": "/run/my-service.sock"}
  ]
}
```

> **Note**: The parser supports both the new object format and the legacy array format for backwards compatibility.

### 3. `args.json` (consumers)

Declares which services this container needs:

```json
{
  "PV_SERVICES_REQUIRED": [
    {"name": "my-service", "target": "/run/pv/services/my-service.sock"}
  ]
}
```

For xconnect service manifest details and supported service types (unix, rest, dbus, drm, wayland), see the [pantavisor xconnect reference](../../pantavisor/docs/reference/pantavisor-xconnect.md) or [pantavisor/docs/overview/xconnect.md](../../pantavisor/docs/overview/xconnect.md).

### Placing a container in the `app` group

Set `PVR_APP_ADD_GROUP = "app"` in the recipe to inherit the group's default `auto_recovery` policy. Containers in the `app` group automatically get restart-on-failure with backoff behaviour unless they provide their own `PV_AUTO_RECOVERY` in `args.json`.

## Building Containers

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-foo
```

Output: `build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-foo.pvrexport.tgz`

## Adding a New Example Container (full workflow)

```bash
# 1. Create recipe
cat > recipes-containers/pv-examples/pv-example-mytest_1.0.bb << 'EOF'
SUMMARY = "My Test Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-mytest"
PVRIMAGE_AUTO_MDEV = "0"
IMAGE_INSTALL += "busybox"
SRC_URI += "file://${PN}.args.json"
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/bin/sh"
EOF

# 2. Create args.json
cat > recipes-containers/pv-examples/files/pv-example-mytest.args.json << 'EOF'
{
  "PV_SERVICES_REQUIRED": [
    {"name": "raw", "target": "/run/pv/services/raw.sock"}
  ]
}
EOF

# 3. Build and deploy for testing
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-example-mytest
cp build/tmp-scarthgap/deploy/images/docker-x86_64/pv-example-mytest.pvrexport.tgz pvtx.d/
```

## Inspecting Pvrexports

Use `pvr` tools to inspect pvrexports — do not manually extract tarballs:

```bash
# Quick inspection — show state JSON
pvr inspect /path/to/container.pvrexport.tgz

# Clone to directory for detailed inspection
pvr clone /path/to/container.pvrexport.tgz /tmp/inspect-dir
cat /tmp/inspect-dir/<container-name>/run.json
```

## Common Issues

### Pseudo Path Mismatch Errors

Errors like `path mismatch [1 link]: ino XXXXX db '...' req '...'` during image builds indicate pseudo database corruption, typically triggered by pvr file operations.

**Fix:**
```bash
kas shell <config.yaml> -c "bitbake -c cleansstate <recipe-name>"
kas build <config.yaml>
```

The `pvroot-image.bbclass` includes `PSEUDO_IGNORE_PATHS` entries to mitigate this for pvr working directories.

### Multiconfig TMPDIR Conflicts

When using `BBMULTICONFIG`, each config must have a separate TMPDIR to avoid conflicts with package feeds, sstate, and deploy directories:

```
TMPDIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-${MULTICONFIG_NAME}-${MACHINE}"
```
