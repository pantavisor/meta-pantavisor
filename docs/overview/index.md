---
title: "Overview"
description: "Architecture and design of Pantavisor and the meta-pantavisor Yocto layer."
sidebar_position: 1
---

# Overview

Conceptual documentation for the Pantavisor runtime and the meta-pantavisor layer. Start here before reading the build or install guides.

## Topics

1. [Pantavisor](pantavisor.md) — what Pantavisor is: container model, atomic updates, cloud control, and the trail/revision system
2. [meta-pantavisor](meta-pantavisor.md) — directory layout, key recipes, BitBake classes, KAS fragments, and layer conventions
3. [Build System](build-system.md) — KAS configuration hierarchy, multiconfig architecture, and the relationship between build targets
4. [Boot Flow](boot-flow.md) — how `boot.cmd.pvgeneric` boots Pantavisor: FIT/trail loading, try-boot, MMC vs NAND/UBIFS, and `PV_BOOT_OEMARGS`
5. [CI](ci.md) — how CI machines, workflows, and build matrix relate to the layer structure
