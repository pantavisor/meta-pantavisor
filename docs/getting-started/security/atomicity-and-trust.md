---
title: Atomicity and trust evidence
description: Published power-fail and rollback test methodology and results that justify trusting Pantavisor as PID 1.
sidebar_position: 1
---

# Atomicity and trust evidence

A runtime you cannot simply delete must clear a higher reliability bar than an
updater you can. This page is where we publish the evidence that Pantavisor's
update path is power-fail safe — the single highest-leverage objection to
trusting Pantavisor as PID 1.

## The guarantee

At every point during an update, a power cut leaves the device able to boot
*some* good revision. Updates are applied as new content-addressed revisions and
switched atomically; a trial revision must affirmatively pass health checks
before it is marked good, otherwise the bootloader reverts.

## Test methodology (to be published with results)

- A power-cut rig (relay or USB-PD switch) interrupts power at randomized points
  across thousands of update cycles.
- After each cut, the device must boot a good revision and report a consistent
  state.
- Results, raw logs, and the rig design are published so the test is
  reproducible.

## Mechanism

- **Bootloader-enforced try/rollback** (U-Boot `bootcount` + a trial/known-good
  revision pair, or `grub-editenv` one-shot).
- **Health-gated commit** on per-container readiness probes with a global
  timeout → auto-rollback.
- **Crash-consistent object store**: objects are written and `fsync`'d before
  the manifest is written and atomically renamed; a manifest is never referenced
  before its objects are durable.
- **Hardware watchdog** as the backstop, fed by PID 1 (Pantavisor).

> **📝 Note**
>
> This page ships with measured results and the rig design as part of hardening
> the trust story. Until then it documents the guarantee and methodology.
