---
sidebar_position: 4
---
# Pantavisor Starter Image

`pantavisor-starter` (`recipes-pv/images/pantavisor-starter.bb`) is the layer's
top-level **deployable image**: a complete, bootable rootfs whose initial
Pantavisor trail (`/trails/0`) is pre-populated with a working set of containers
and the board's BSP. It is what you flash to get a device that boots Pantavisor
and brings up a usable system out of the box.

```bitbake
inherit image pvroot-image pantavisor-docs

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi"
PVROOT_IMAGE_BSP       ?= "core-image-minimal"
```

## What "starter" means

Unlike a plain Yocto image (a package set in a rootfs), a pvroot image is a
**Pantavisor state**. The rootfs is the `pantavisor-pvroot` skeleton, and the
real payload is an initial signed trail under `/trails/0` assembled by mixing in
container `pvrexport` bundles plus the BSP. The "starter" image is the opinionated
default mix — enough to boot, get on the network, and be claimed/managed — as
opposed to the bare [`pantavisor-remix`](#related-image-recipes) which ships only
the SDK container.

## What it ships

The default trail is built from two variables (see
[`pvroot-image.bbclass`](meta-pantavisor.md)):

| Variable | Role | Default |
|----------|------|---------|
| `PVROOT_CONTAINERS_CORE` | Containers baked **into the initial trail** (`pvr deploy` into `/trails/0`) | `pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi` |
| `PVROOT_CONTAINERS` | Containers staged as **factory packages** (`factory-pkgs.d/`), installed on first boot | *(none)* |
| `PVROOT_IMAGE_BSP` | Proto rootfs the BSP's modules/firmware come from | `core-image-minimal` |

The core containers in the starter mix:

| Container | Purpose |
|-----------|---------|
| `pv-pvr-sdk` | PVR SDK / local management container |
| `pv-alpine-connman` | ConnMan network backend (the WiFi/networking stack) |
| `pvwificonnect` | WiFi provisioning — AP, captive portal, tethering (see [pvwificonnect](../examples/pvwificonnect.md)) |
| `pv-avahi` | mDNS/zeroconf service discovery |

The `pantavisor-bsp` pvrexport (kernel, initramfs, DTBs, modules, firmware) is
**always** mixed in, regardless of the container list — that is what makes the
trail bootable on the target machine.

## How the image is assembled

The work happens in `pvroot-image.bbclass`'s `do_rootfs_pvroot` task (runs after
`do_rootfs`, before `do_image`):

1. **Skeleton trail** — `pvr checkout -c` lays down the device skeleton in
   `/trails/0`, then `pvr sig add` / `add` / `commit` create the initial signed
   revision.
2. **Mix in containers** — for each `PVROOT_CONTAINERS_CORE` entry the matching
   `*.pvrexport.tgz` from `DEPLOY_DIR_IMAGE` is unpacked and `pvr deploy`-ed into
   the trail. `PVROOT_CONTAINERS` entries are instead copied into
   `factory-pkgs.d/` to be applied on first boot.
3. **Mix in the BSP** — `pantavisor-bsp-${MACHINE}.pvrexport.tgz` is always
   deployed into the trail.
4. **Sign** — the trail is signed with the developer CA
   (`pv-developer-ca_${PVS_VENDOR_NAME}`), so unsigned/tampered states are
   rejected at boot.
5. **Boot glue** (`do_rootfs_boot_scr`) — `boot.scr` is copied to `/boot`, and on
   UBIFS machines `oemEnv.txt` is placed at the rootfs root (where `boot.scr`
   expects it).

Container builds depend on `do_deploy`; the BSP on `do_compile`/`do_image_complete`
— these are wired automatically by the `__anonymous` hook in `pvroot-image.bbclass`.

## Build artifacts

After a build, in `build/tmp-${codename}/deploy/images/${machine}/`:

| Artifact | Description |
|----------|-------------|
| `pantavisor-starter-${machine}.wic[.bz2]` | Flashable disk image (partition layout from the machine's WKS file) |
| `pantavisor-starter-${machine}.rootfs.*` | Rootfs tarball with the populated `/trails/0` |
| `pantavisor-README.md` | Concatenated flashing guide (see below) |
| `pantavisor-starter-*.docs.tar.zst` / `pantavisor-reference-documentation*.html.tar.zst` | Bundled docs (from `pantavisor-docs`) |

### Flashing README

Via the `pantavisor-docs` inherit and `do_deploy_readme`, the image emits a
`pantavisor-README.md` by concatenating, in order:

```
docs/pantavisor.md  +  PV_FLASH_README_DEPS (e.g. toradex.md, uuu.md)  +  PV_FLASH_README
```

`PV_FLASH_README` and `PV_FLASH_README_DEPS` are set per machine in
`kas/machines/<machine>.yaml` (via `local_conf_header`), so each board ships the
right [install guide](../how-to-install/index.md) next to its image.

## Building

```bash
./kas-container build kas/build-configs/release/<machine>-scarthgap.yaml \
    --target pantavisor-starter
```

Because the starter aggregates the BSP and every core container, a full build
also builds `pantavisor-bsp`, `pantavisor-initramfs`, and the core container
recipes. See [Get Started](../how-to-build/get-started.md) for prerequisites and
the KAS workflow.

## Customizing the mix

Override the container set from a machine/distro include or `local.conf` — use
assignment, since these are the image's content list:

```bitbake
# Swap the default mix for your product's containers
PVROOT_CONTAINERS_CORE = "pv-pvr-sdk pv-alpine-connman my-app-container"

# Ship an extra container as a first-boot factory package instead of in-trail
PVROOT_CONTAINERS = "my-optional-app"
```

Authoring a container to add here is covered in
[Container Development](../how-to-build/container-development.md).

## Related image recipes

| Recipe | Description |
|--------|-------------|
| `pantavisor-starter.bb` | This image — BSP + core containers, ready to flash |
| `pantavisor-remix.bb` | Minimal pvroot image: only `pv-pvr-sdk`, just enough to boot |
| `pantavisor-bsp.bb` | BSP pvrexport (kernel + initramfs + modules + firmware); mixed into every pvroot image |
| `pantavisor-initramfs.bb` | The Pantavisor-as-init initramfs the BSP wraps |
| `empty-image.bb` | Empty proto rootfs used as a BSP modules/firmware source |
| `pantavisor-appengine` | Docker-based image for local appengine testing (not a flashable device image) |

## Related

- [meta-pantavisor](meta-pantavisor.md) — layer layout and key recipes/classes
- [Build System](build-system.md) — KAS hierarchy, multiconfig, and build targets
- [Boot Flow](boot-flow.md) — how the BSP boots Pantavisor from U-Boot
- [Install guides](../how-to-install/index.md) — flashing the starter image per board
