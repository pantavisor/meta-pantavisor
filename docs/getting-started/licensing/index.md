---
title: Project, licensing, and governance
description: Open-source licensing of the Pantavisor stack — MIT on-device, Apache-2.0 for backend services — and the Pantacor Hub boundary.
sidebar_position: 15
---

# Project, licensing, and governance

Risk-averse teams evaluate licensing before features. This page states the
license of every Pantacor-authored project the documentation covers, so the
open-source boundary is explicit.

## Licensing model

Pantacor publishes a simple licensing scheme (source: the canonical
[`pantacor/licensing`](https://github.com/pantacor/licensing) repository):

:::info[The rule of thumb]
- **Pantavisor code that runs on the device → [MIT](https://opensource.org/license/mit).**
- **Backend services → [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0)** (adds an explicit patent grant).
:::

MIT on the device gives commercial product teams maximum flexibility with no
copyleft obligations on their own application containers. Every project ships a
top-level `LICENSE`/`COPYING` file with the full license text — treat that file
as authoritative for the project (see the verified per-project table below).

## Per-project licenses

Licenses verified against each project's repository:

| Project | Role | License | Source |
|---|---|---|---|
| **Pantavisor** | On-device supervisor / PID 1 | **MIT** | [github.com/pantavisor/pantavisor](https://github.com/pantavisor/pantavisor) |
| **meta-pantavisor** | Yocto BSP layer (builds the on-device system) | **MIT** | [github.com/pantavisor/meta-pantavisor](https://github.com/pantavisor/meta-pantavisor) |
| **pvr** | CLI for inspecting/building/deploying revisions | **Apache-2.0** | [github.com/pantacor/pvr](https://github.com/pantacor/pvr) |
| **pvr-sdk** | SDK container/tooling around `pvr` | **MIT** | [gitlab.com/pantacor/pv-platforms/pvr-sdk](https://gitlab.com/pantacor/pv-platforms/pvr-sdk) |
| **Pantahub (pantahub-base)** | Hub backend / device API server | **Apache-2.0** | [github.com/pantacor/pantahub-base](https://github.com/pantacor/pantahub-base) |

## Open source vs. the hosted service

The **code** above is fully open source — including `pantahub-base`, the Hub
backend (Apache-2.0). What is **commercial** is the *hosted* **Pantacor Hub**
service (the managed fleet/device-management offering at
[pantacor.com](https://www.pantacor.com)), not the license of the code. You can
self-host the open components; the commercial relationship is the managed
service and support, not a closed core.

## Bundled third-party components

A built Pantavisor image also contains upstream components that keep their own
licenses — for example the container runtime and base userland:

| Component | Typical license |
|---|---|
| LXC (Pantavisor's build) | LGPL-2.1-or-later (some bundled tools GPL-2.0) |
| BusyBox (`busybox-pv`) | GPL-2.0 |
| `libthttp` | MIT |
| `kas` (build tool) | MIT |

These are not Pantacor-authored, and their terms govern the corresponding files
in an image. To enumerate the exact components and licenses in any image you
ship, enable Yocto's `create-spdx` class in your meta-pantavisor build (e.g.
`INHERIT += "create-spdx"` in `local.conf`) to generate a per-image **SPDX
SBOM**.

:::note[Verify before redistribution]
Licenses can change between releases. For any image you redistribute, treat the
generated SBOM and each project's top-level `LICENSE` file as the authoritative
source, not this summary.
:::
