---
title: Operate devices
description: Update, roll back, recover, and observe Pantavisor devices and fleets.
sidebar_position: 6
---

# Operate devices

This section covers day-to-day operation of Pantavisor devices: accessing them
over serial, the local network, or Pantahub; deploying updates; rolling back;
and monitoring what is running.

## Tasks

- [Device access](./device-access/index.md) — serial console, SSH, the pvtx web UI,
  and remote management through Pantahub
- [Update an application](/meta-pantavisor/getting-started/develop/application/install/) — clone the device
  state, add or update containers, and deploy a new revision
- [Roll back a failed update](/meta-pantavisor/getting-started/troubleshooting/faq#what-happens-if-an-ota-update-fails)
  — Pantavisor rolls back automatically when an update fails; see the FAQ for
  how it works
- [Remote logs](./device-access/remote-pantahub.md) — stream device logs through
  Pantahub, or view them live in the [pvtx web UI](./device-access/pvtx-ui.md#logs)
- [Monitor a device](./device-access/pvtx-ui.md) — live resource stats, device
  metadata, and configuration in the pvtx web UI

Guides for canary rollouts, drift detection, air-gapped workflows, and
watchdog integration are coming soon.
