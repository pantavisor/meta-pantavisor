---
title: Add Your Application
sidebar_position: 21
description: Two ways to turn an application into a Pantavisor container — pull an existing OCI image with pvr, or bake it into the BSP as a Yocto recipe.
---

Every Pantavisor app is an LXC container with a `run.json` manifest,
versioned in the device's [revision trail](../../../overview/glossary.md#revision).
There are two ways to get your application into that shape, and which one
you want depends on what you're starting from.

## Which route do I need?

| | Already have a Docker/OCI image | Building the BSP image itself |
|---|---|---|
| **Route** | Pull it with `pvr` | Wrap it as a Yocto recipe |
| **Needs Yocto?** | No | Yes |
| **Speed** | Minutes | A full BitBake build |
| **Where it lives** | Added to a device's revision trail directly | Part of the reproducible BSP build, tracked in this layer's git history |
| **Use when** | You're deploying to a device you already have running | You're building/customizing images for a fleet, or the app must ship inside the initial image |

<div style="display: flex; justify-content: center;">

<pre>
                     Have an application?
                              │
            ┌─────────────────┴─────────────────┐
            │                                    │
  Already an OCI/Docker image             Building the BSP image
            │                                    │
  pvr app add --from &lt;image&gt;          inherit core-image
    --platform &lt;arch&gt;                   container-pvrexport
            │                                    │
  pvr add . && pvr commit             kas-container build --target &lt;recipe&gt;
            │                                    │
  pvr post &lt;device&gt;                      pvr inspect *.pvrexport.tgz
            │                                    │
            └─────────────────┬──────────────────┘
                              │
              Running container in the device's
                         revision trail
</pre>

</div>

## Route 1 — Pull an existing OCI image

If your application already builds as a Docker/OCI image (Docker Hub, GHCR,
a private registry — any OCI-compatible host), `pvr app add` pulls it,
converts it to a SquashFS container, and stages it as a new device
revision. No Yocto toolchain involved.

```bash
pvr clone http://<device-ip>:12368/cgi-bin mydevice
cd mydevice
pvr app add myapp --from registry.example.com/team/myapp:v1 --platform linux/arm64
pvr add . && pvr commit -m "add myapp container"
pvr post http://<device-ip>:12368
```

Full walkthrough, including scanning for the device, private-registry auth,
and verifying the deploy: [Install with the pvr CLI](./install/local-pvr.md).

## Route 2 — Bake it into the BSP as a Yocto recipe

If you're building this layer's images and want the app shipped as part of
the reproducible BSP build (not added to a device after the fact), wrap it
as an OE recipe using the same pattern as
`recipes-containers/pv-examples/`:

```bitbake
SUMMARY = "My App Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-myapp"
PVRIMAGE_AUTO_MDEV = "0"
IMAGE_INSTALL += "myapp-package"
SRC_URI += "file://${PN}.args.json"
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/myapp"
PVR_APP_ADD_GROUP = "app"
```

`inherit core-image container-pvrexport` is what turns a normal OE image
recipe into a Pantavisor-importable container; `args.json` (and
`services.json`, if your app talks to other containers) wire it into the
[xconnect](../../../overview/glossary.md#xconnect) service mesh.
`PVR_APP_ADD_GROUP = "app"` gets you restart-on-failure auto-recovery for
free.

Build it and inspect the result:

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml \
    --target pv-myapp

pvr inspect build/tmp-scarthgap/deploy/images/docker-x86_64/pv-myapp.pvrexport.tgz
```

Full recipe reference, `services.json`/`args.json` details, and the
complete add-a-container workflow:
[Container Development](../../../overview/container-development.md).

## After either route

- [Configure](./configure.md) — overlay files or edit `run.json` post-deploy.
- [`pvcontrol`](../cli-tools/pvcontrol.md) — verify the container's runtime
  state (`pvcontrol container ls`) after it's live.
