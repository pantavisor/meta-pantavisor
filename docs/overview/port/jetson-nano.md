---
title: Jetson Nano 4 GB bring-up
description: Experimental local Pantavisor build for the original microSD Jetson Nano with CUDA.
---

This target is for the original **Jetson Nano 4 GB development module
(P3448-0000)** on NVIDIA's reference carrier. It uses microSD storage. The
2 GB, production eMMC, and Orin Nano modules are different targets.

## Local build

Run from the repository root:

```bash
./kas-container build kas/build-configs/jetson-nano-kirkstone.yaml
```

For a dependency-resolution check without compilation:

```bash
./kas-container shell kas/build-configs/jetson-nano-kirkstone.yaml \
    -c 'bitbake -n pantavisor-starter'
```

The configuration pins OE4T's `kirkstone-l4t-r32.7.x` layer, which provides
L4T R32.7.6, Linux 4.9, and CUDA 10.2. NVIDIA's binary userspace requires
glibc. The CUDA recipes supply a separate GCC 8 compiler; the entire system
does not need to use GCC 8. LXC 3 and cgroup v1 are selected for this kernel.
Do not replace this layer with the regular `kirkstone` or `scarthgap`
meta-tegra branches: those target newer NVIDIA BSPs.

## Artifacts and boot

Outputs are under `build/tmp-kirkstone/deploy/images/jetson-nano-devkit/`:

- `pantavisor-starter-jetson-nano-devkit.sdcard.gz`: compressed whole-card
  image for a microSD card (16 GB or larger).
- `pantavisor-starter-jetson-nano-devkit.tegraflash.tar.gz`: NVIDIA recovery
  flashing tools, QSPI firmware, partition layout, and the APP filesystem.
- `pantavisor-bsp-jetson-nano-devkit.pvrexport.tgz`: Pantavisor BSP export.
- `pv-jetson-cuda.pvrexport.tgz`: CUDA diagnostic container.

The tegraflash archive supplies `doflash.sh` for recovery flashing and
`dosdcard.sh` for recreating a raw `.sdcard` image. A rootfs `.ext4` file is
**not** a whole-card image. Before running a flashing script, inspect its
arguments and NVIDIA's recovery procedure for the attached board. Initial
QSPI firmware may need to be flashed even when booting from microSD.

The APP filesystem is labeled `root` and holds both `/boot` and Pantavisor
storage. Its boot script reads the revision from `/boot/uboot.txt`, tracks
try-boot state in `/pv.env`, and boots the revision's kernel and initramfs.
It preserves the device tree patched by NVIDIA's CBoot firmware, including
memory reservations needed by the GPU. Updating that firmware/device tree
through Pantavisor is not implemented by this target.

## CUDA acceptance test

The factory revision includes `pv-jetson-cuda`. Its startup runs
`deviceQuery` and `vectorAdd` before signaling READY. The latter launches a
CUDA kernel and validates the result; enumeration alone is insufficient.
The container declares the required `nvidia` driver, mapped to `nvgpu`, and
its mdev rules expose `nvhost*` and `nvmap` device nodes.

On a running device, enter the container and repeat the tests:

```bash
pventer -c pv-jetson-cuda
/usr/bin/cuda-samples/deviceQuery
/usr/bin/cuda-samples/vectorAdd
```

Both must pass. A successful compilation or a successful CPU test does not
establish CUDA support on hardware. This first board target contains CUDA
diagnostics; llama.cpp, a chat model, and a chat UI are subsequent app builds.

## API build integration

The KAS target is intended to be built and tested locally before being
registered in the cloud build catalog. It produces a native NVIDIA
`tegraflash` artifact, not a Raspberry Pi image-base archive. API image
assembly must understand that format before it can compose factory images
from arbitrary application builds. Do not use the Raspberry Pi image-base
assembler for this target.
