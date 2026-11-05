---
sidebar_position: 12.5
description: Compile Pantavisor with the prebuilt SDK, without a Yocto build.
---
# Pantavisor SDK

The SDK released with each tag compiles Pantavisor itself, not only
[containers](../getting-started/develop/application/container-sdk.md). Use it
to build and check a Pantavisor change without a Yocto build of this layer.

The SDK is built with the board distro (`panta-distro`: musl, and the board
`PANTAVISOR_FEATURES`). Its sysroot has the libraries Pantavisor links
against.

The SDK does not package Pantavisor for a device. To run a change on a
device, build it through the layer: see
[Pantavisor Development](pantavisor-development.md).

## Install

Download the installer for your device's CPU as shown in
[Build Containers with the SDK](../getting-started/develop/application/container-sdk.md#install),
then:

```bash
sh ./pv-sdk-<tag>-armv8.sh -d ~/pv-sdk-armv8 -y
. ~/pv-sdk-armv8/environment-setup-*
```

## Build Pantavisor

The environment script exports `CMAKE_TOOLCHAIN_FILE`, so a plain `cmake`
cross-compiles for the device, in scripts as well as in the shell:

```bash
git clone https://github.com/pantavisor/pantavisor.git
cd pantavisor
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j"$(nproc)"
DESTDIR="$PWD/pv-install" cmake --install build --strip
```

This builds with Pantavisor's default options. To match a board build, pass
the `-D` options from `EXTRA_OECMAKE` in `recipes-pv/pantavisor/pantavisor_git.bb`
for the features you need, e.g. `-DPANTAVISOR_XCONNECT=ON`.

The version string comes from `git describe`, so build from a clone, not a
source archive. The release builds the commit in `PANTAVISOR_SRCREV`
(`recipes-pv/pantavisor/pantavisor.inc`); start from it to change only what
you mean to.

`pv-install` then holds the installed files, e.g.
`pv-install/usr/bin/pantavisor`, built for the device's CPU:

```bash
file pv-install/usr/bin/pantavisor
```

```
pv-install/usr/bin/pantavisor: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-musl-aarch64.so.1, ...
```

## Add a package to the SDK

Libraries and headers for the SDK's sysroot go in `RDEPENDS:${PN}` in
`recipes-pv/pv-sdk-tools/packagegroup-pv-sdk-target.bb`. List the `-dev`
package, and `-staticdev` as well to link statically:

```bitbake
RDEPENDS:${PN} = " \
    ...
    zlib-dev \
    zlib-staticdev \
"
```

Tools that run on the host are `nativesdk-` packages: add those to `RDEPENDS` in
`recipes-pv/pv-sdk-tools/nativesdk-pv-sdk-tools.bb`.

Rebuild the SDK and check that the package landed in its sysroot:

```bash
./kas-container shell kas/machines/docker-armv8.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:kas/sdk.yaml \
    -c "bitbake -c populate_sdk pv-sdk"
grep zlib-dev build/tmp-scarthgap-sdk/deploy/sdk/pv-sdk-armv8-x86_64.target.manifest
```
