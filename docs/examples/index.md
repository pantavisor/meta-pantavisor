---
title: "Examples"
description: "Worked examples for building containers in meta-pantavisor: Yocto-built containers and xconnect service mesh patterns."
sidebar_position: 4
---

# Examples

Reference implementations for building your own Pantavisor containers — both Yocto-built containers (assembled from layer packages) and the xconnect service-mesh example containers in `recipes-containers/pv-examples/`.

## Topics

1. [Building a Yocto Container for Pantavisor](yocto-container.md) — author an image recipe that builds a daemon from source (e.g. `tailscale` from `meta-networking`) and ships it as a `.pvrexport.tgz`, including `config.json` (OCI) vs `args.json` (LXC)
2. [xconnect Examples](xconnect-examples.md) — Unix socket, REST, D-Bus, DRM, and Wayland proxy patterns with provider/consumer container pairs

## Related

- [pantavisor xconnect overview](../../pantavisor/overview/xconnect.md) — how xconnect works
- [pantavisor xconnect reference](../../pantavisor/reference/pantavisor-xconnect.md) — manifest format and socket types
- [Container Development](../how-to-build/container-development.md) — how to author your own containers
