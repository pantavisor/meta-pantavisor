---
title: Develop applications
description: Build, configure, and ship app containers on Pantavisor.
sidebar_position: 4
---

# Develop applications

Apps are versioned and updated independently of the [base](../security/trust-model.md)
— the frozen, certified BSP + Pantavisor runtime layer described in the trust
model. A CVE fix in your app ships as a small container layer — not a
full-image flash — and never touches the certified base. See the
[benchmarks](/meta-pantavisor/getting-started/benchmarks) for the size and time
difference.

## Manage applications

- [Install apps](./application/install/index.md) — add [containers](../../overview/glossary.md#container) with the `pvr` CLI, the pvtx web UI, or remotely via [Pantahub](./application/install/remote-pantahub.md)
- [Configure](./application/configure.md) — overlay files and runtime manifests through the [revision](../../overview/glossary.md#revision) workflow
- [View](./application/view.md) — container status, logs, and the pvtx web UI
- [Access](./application/access-applications.md) — enter containers, reach their ports, and wire services with pv-xconnect
- [Remove](./application/remove.md) — drop a container from the device state and deploy

## Tooling and deeper development

- [CLI tools](./cli-tools/index.md) — `pvr`, `pvtx`, and `pvcontrol` cheatsheets and workflows
- [Container development](../../overview/container-development.md) — build example containers in the meta-pantavisor Yocto layer
- [Pantavisor runtime development](../../overview/pantavisor-development.md) — hack on the Pantavisor runtime itself with the kas workspace

For exhaustive, generated CLI documentation, see the [Reference](/pantavisor/overview).
