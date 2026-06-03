---
title: "meta-pantavisor Documentation"
description: "Build, install, and develop with Pantavisor on embedded Linux using the meta-pantavisor Yocto layer."
sidebar_position: 1
---

# meta-pantavisor Documentation

meta-pantavisor is the Yocto/OpenEmbedded layer for building Pantavisor-based BSP images. It provides recipes, BitBake classes, and KAS configurations for embedded Linux products.

## Sections

| Section | Topics |
|---------|--------|
| [Overview](overview/) | What Pantavisor is, what this layer provides, how the build system works |
| [How to Build](how-to-build/) | First build, local source development, container authoring, manifest auditing |
| [How to Install](how-to-install/) | Flashing images to hardware: SD card, Docker, Tezi, UUU, and board-specific guides |
| [Examples](examples/) | xconnect service mesh example containers |
| [Testing](testing/) | Development workflow, automated test runner, and structured test plans |
| [CI](ci/) | CI pipeline overview, machine matrix, release builds, and tag-sync workflow |

## Reading Order

New to meta-pantavisor? Follow this path:

1. [What is Pantavisor?](overview/pantavisor.md) — understand the runtime
2. [meta-pantavisor Overview](overview/meta-pantavisor.md) — understand the layer
3. [Get Started](how-to-build/get-started.md) — build your first image
4. [Flash via SD Card](how-to-install/sdcard.md) — install on hardware
5. [Container Development](how-to-build/container-development.md) — author app containers
6. [Pantavisor Development](how-to-build/pantavisor-development.md) — develop against local pantavisor source
