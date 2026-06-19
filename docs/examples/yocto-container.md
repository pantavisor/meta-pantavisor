---
sidebar_position: 1
---
# Building a Yocto Container for Pantavisor

This walkthrough shows how to build a container **from source with Yocto/OpenEmbedded** and ship it as a Pantavisor container, using the `pv-tailscale` recipe as a worked example. Unlike a `docker pull`, the rootfs is assembled by BitBake from layer packages, signed, and exported as a `.pvrexport.tgz` that Pantavisor installs into a revision.

Use this when you want a container whose contents are reproducible, license-audited, and built for the device architecture from the same layers as the rest of the BSP — e.g. pulling a daemon out of `meta-networking` rather than fetching a prebuilt image.

> For service-mesh (xconnect) example containers, see [xconnect Examples](xconnect-examples.md). For local source iteration with the workspace overlay, see [Container Development](../how-to-build/container-development.md).

## How a Pantavisor container is built

A container recipe is an **image recipe**. Two BitBake classes do the work:

| Class | Role |
|-------|------|
| `image` | Assembles a root filesystem from `IMAGE_INSTALL` packages (same machinery as a normal Yocto image, but minimal — no `packagegroup-core-boot`). |
| `container-pvrexport` | Adds the `pvrexportit` image type: takes the rootfs, runs `pvr app add --type rootfs`, attaches metadata, signs it, and exports `${PN}.pvrexport.tgz`. |

The pipeline is:

```
IMAGE_INSTALL packages ─▶ rootfs ─▶ squashfs ─▶ pvr app (run.json + config) ─▶ sign ─▶ ${PN}.pvrexport.tgz
```

The `.pvrexport.tgz` is then referenced from an image's `PVROOT_CONTAINERS_CORE` and installed into the device revision (see [Wiring it into an image](#wiring-it-into-an-image)).

## Anatomy of a container recipe

A minimal recipe needs the inherit line, an image basename, the `pvrexportit` fstype, and the packages to install. Here is the skeleton (`recipes-containers/pantavisor/pv-tailscale_1.1.bb`):

```bitbake
SUMMARY = "Pantavisor Tailscale VPN container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-tailscale"
PVRIMAGE_AUTO_MDEV = "1"
IMAGE_FSTYPES = "pvrexportit"

# Packages that make up the container rootfs. tailscale/tailscaled come from
# meta-networking (built from the tailscale.com Go module, GO_IMPORT = "tailscale.com").
IMAGE_INSTALL += "busybox tailscale iptables ca-certificates base-files base-passwd"

# The container's per-app LXC + OCI config are shipped as files in SRC_URI.
do_fetch[noexec] = "0"
do_unpack[noexec] = "0"
SRC_URI += "file://args.json \
            file://config.json \
            file://pv-tailscale-start.sh \
"

PVR_APP_ADD_EXTRA_ARGS += " --volume ovl:/tmp:permanent \
                            --volume ovl:/var/lib/tailscale:permanent"
PVR_APP_ADD_GROUP = "platform"
```

Key knobs:

| Variable | Meaning |
|----------|---------|
| `IMAGE_INSTALL` | Packages baked into the rootfs. Pull daemons from any layer in the build (`meta-networking`, `meta-oe`, …). |
| `IMAGE_FSTYPES = "pvrexportit"` | Produce the Pantavisor export instead of a normal image type. |
| `PVRIMAGE_AUTO_MDEV` | `1` auto-generates an mdev rule (`.* 0:0 666`) so device nodes appear inside the container. Set `0` for pure userspace containers. |
| `PVR_APP_ADD_GROUP` | Pantavisor group the container runs in (`root`, `platform`, `app`). Groups carry default restart/recovery policy. |
| `PVR_APP_ADD_EXTRA_ARGS` | Extra `pvr app add` flags — most often `--volume ovl:<path>:permanent` for state that must survive reboots/updates. |

> **`base-files` + `base-passwd`**: `inherit image` is deliberately minimal, so it drops the `/proc /sys /dev` mountpoint dirs and `/etc/passwd` that the container's `lxc.mount.auto` (cgroup) and user setup need. Add these two packages if your container aborts at start.

The recipe also installs the entrypoint script and pre-creates runtime dirs via a rootfs postprocess:

```bitbake
install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-tailscale-start.sh ${IMAGE_ROOTFS}${bindir}/pv-tailscale-start
    install -d ${IMAGE_ROOTFS}/var/lib/tailscale
    install -d ${IMAGE_ROOTFS}/var/run/tailscale
    install -d ${IMAGE_ROOTFS}/dev/net
}
ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "
```

Finally, a no-op `do_deploy` avoids a double-deploy of the `.pvrexport.tgz` (the sstate path already deploys it):

```bitbake
fakeroot do_deploy() {
    :
}
addtask deploy after do_image_complete before do_build
```

## `config.json` vs `args.json` — the two config files

This is the part most worth understanding. A Pantavisor container carries **two** config files, picked up automatically by `container-pvrexport` when present in the recipe's `SRC_URI`:

| File | Layer | Controls |
|------|-------|----------|
| `config.json` | OCI / Docker `--config-json` | What the container *runs*: `Entrypoint`, `Env`, `WorkingDir`, `Volumes`. |
| `args.json` | Pantavisor / LXC `--arg-json` | How the container is *confined and scheduled*: Linux capabilities, namespaces, restart policy, volume imports. |

### `config.json` (OCI runtime)

Standard OCI container config. For `pv-tailscale`:

```json
{
    "Entrypoint": ["/usr/bin/pv-tailscale-start"],
    "Env": [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        "TS_STATE_DIR=/var/lib/tailscale",
        "TS_SOCKET=/var/run/tailscale/tailscaled.sock",
        "TS_TUN=tailscale0",
        "TS_USERSPACE=false"
    ],
    "WorkingDir": "/",
    "Volumes": { "/tmp": {}, "/var/lib/tailscale": {} }
}
```

### `args.json` (LXC confinement + Pantavisor scheduling)

This is where you grant the kernel capabilities the daemon needs and set the restart policy. `pv-tailscale` needs `net_admin`/`net_raw` to manage the tun interface, routes, and iptables, plus `mknod` to create `/dev/net/tun`:

```json
{
    "PV_GROUP": "platform",
    "PV_LXC_CAP_KEEP": [
        "net_admin", "net_raw", "net_bind_service",
        "setuid", "setgid", "chown", "dac_override",
        "sys_chroot", "mknod", "kill"
    ],
    "PV_RESTART_POLICY": "system"
}
```

Common `args.json` keys:

| Key | Purpose |
|-----|---------|
| `PV_GROUP` | Pantavisor group (matches `PVR_APP_ADD_GROUP`). |
| `PV_LXC_CAP_KEEP` | Allowlist of Linux capabilities the container keeps (everything else is dropped). |
| `PV_LXC_NAMESPACE_KEEP` | Namespaces shared with the host (e.g. `"net pid ipc"`). |
| `PV_RESTART_POLICY` | `system` (lifecycle tied to the platform) or `container` (driveable via the lifecycle API). |
| `PV_VOLUME_IMPORTS` | Bind volumes from the host/other containers, e.g. `"os:/pvrun/dbus:/var/run/dbus"`. |

> Both files also support a per-recipe `${PN}.args.json` / `${PN}.config.json` variant, which takes precedence over the plain names — useful when one `files/` directory serves several recipes.

## Pulling a daemon from `meta-networking`

`meta-networking` is already a layer in the BSP/appengine builds (`kas/bsp-base.yaml`, `kas/appengine-base.yaml`). Its `tailscale` recipe cross-compiles the upstream Go module rooted at `tailscale.com` (`GO_IMPORT = "tailscale.com"`) and provides the `tailscale` and `tailscaled` binaries. Shipping the client is then just:

```bitbake
IMAGE_INSTALL += "tailscale iptables ca-certificates"
```

The **kernel side** is handled separately by the `tailscale` `PANTAVISOR_FEATURE` (a default in `classes/pvbase.bbclass`): `recipes-kernel/linux/linux-%.bbappend` pulls in `tailscale-iptables.cfg` (or `tailscale-nftables.cfg` if `nftables` is in `IMAGE_INSTALL`), enabling `CONFIG_TUN`, `CONFIG_WIREGUARD`, and the NAT/MARK targets tailscaled programs. So a container that installs `iptables` gets the matching iptables-legacy kernel backend automatically.

The entrypoint then starts the daemon and joins the tailnet, reading the auth key from Pantavisor user-meta so no secret is baked into the read-only image:

```sh
tailscaled --state="$STATE_DIR/tailscaled.state" --socket="$SOCK" --tun="$TUN" &
# ... wait for socket ...
tailscale --socket="$SOCK" up --hostname="$tshostname" --authkey="$authkey"
```

(See `recipes-containers/pantavisor/pv-tailscale/pv-tailscale-start.sh` for the full version, which falls back to `--tun=userspace-networking` when no tun device is available and re-applies `up` when the key is provisioned later — mirroring `pv-avahi-start.sh`.)

## Wiring it into an image

The recipe's `PN` (`pv-tailscale`) is what images and Kconfig reference.

- **Kconfig** already exposes it (`Kconfig`):

  ```kconfig
  config CONTAINER_PV_TAILSCALE
      bool "pv-tailscale"
  config KAS_LOCAL_PV_TAILSCALE
      string
      default "PVROOT_CONTAINERS_CORE += \"pv-tailscale\"" if CONTAINER_PV_TAILSCALE
  ```

  After changing Kconfig, run `.github/scripts/makemachines`.

- **Directly in an image recipe** — add the `PN` to `PVROOT_CONTAINERS_CORE`:

  ```bitbake
  PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi pv-tailscale"
  ```

## Building and inspecting

Build just the container:

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-tailscale
```

Output:

```
build/tmp-scarthgap/deploy/images/docker-x86_64/pv-tailscale.pvrexport.tgz
```

Inspect with the `pvr` tools (never extract the tarball by hand):

```bash
pvr inspect build/tmp-scarthgap/deploy/images/docker-x86_64/pv-tailscale.pvrexport.tgz

pvr clone build/.../pv-tailscale.pvrexport.tgz /tmp/inspect
cat /tmp/inspect/pv-tailscale/run.json   # merged LXC + OCI config
```

To drop the container into a running test device for iteration, copy the `.pvrexport.tgz` into `pvtx.d/` and let Pantavisor apply it (see [Container Development](../how-to-build/container-development.md#inspecting-pvrexports)).

## Checklist for a new container

1. `recipes-containers/<dir>/<pn>_<ver>.bb` — `inherit image container-pvrexport`, set `IMAGE_BASENAME`, `IMAGE_FSTYPES = "pvrexportit"`, `IMAGE_INSTALL`.
2. `config.json` — entrypoint, env, volumes (OCI).
3. `args.json` — capabilities, group, restart policy (LXC/Pantavisor).
4. Entrypoint script installed via `ROOTFS_POSTPROCESS_COMMAND`, persistent state on `--volume ovl:<path>:permanent`.
5. Add the `PN` to an image's `PVROOT_CONTAINERS_CORE` (and a Kconfig entry if it should be user-selectable; rerun `.github/scripts/makemachines`).
6. Build with `--target <pn>` and verify with `pvr inspect`.

## Related

- [Container Development](../how-to-build/container-development.md) — workspace iteration, building, inspecting pvrexports, common build issues
- [xconnect Examples](xconnect-examples.md) — service-mesh container patterns
- [meta-pantavisor overview](../overview/meta-pantavisor.md) — `PANTAVISOR_FEATURES` (including `tailscale`) and layer layout
