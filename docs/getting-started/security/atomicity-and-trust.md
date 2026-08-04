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

- **Bootloader-enforced try/rollback**: a one-shot trial boot of the new
  revision (`pv_try`/`pv_trying` markers, or `grub-editenv` one-shot on GRUB
  machines) — not a multi-attempt bootcount. The first failure or power cut
  during the trial falls back to the last committed revision on the next
  boot. See [Boot Flow](/meta-pantavisor/overview/boot-flow) for the exact
  sequence.
- **Health-gated commit** on per-container readiness probes with a global
  timeout → auto-rollback.
- **Crash-consistent object store**: objects are written and `fsync`'d before
  the manifest is written and atomically renamed; a manifest is never referenced
  before its objects are durable.
- **Hardware watchdog** as the backstop, fed by PID 1 (Pantavisor).

## What's on the device if power is cut, by stage

Derived from the mechanism above and [Boot Flow](/meta-pantavisor/overview/boot-flow)
— this is a logical walkthrough of the documented mechanism, not a substitute
for the empirical test results below, which cover the same ground by
actually cutting power.

| Stage | State after a cut here |
|---|---|
| Mid-download | The new revision's objects aren't all `fsync`'d yet, so its manifest is never written or referenced. The device boots the last committed revision next power-up; there's nothing to roll back. |
| Mid-write of an object | Same as above — an unfsync'd, unreferenced object is simply orphaned and re-fetched on retry. |
| After write, before reboot | All objects are durable and the new revision's manifest is atomically renamed in, but `pv_try` isn't set yet — the device still boots the previously committed revision. |
| Mid-reboot into the trial revision | If `pv_try` was already recorded as attempted before the cut, the next boot falls back to the committed revision. If the record itself didn't persist (this write is skipped on UBI/NAND — see Boot Flow), the device retries the same trial once more. |
| After boot, before the health check commits | `pv_try`/`pv_trying` is already recorded as attempted, so the next boot falls back to the last committed revision automatically — no operator action needed. The hardware watchdog covers the case where the device hangs instead of losing power outright. |

## Boot-attempt limit

The bootloader-side mechanism above is a single trial attempt, not a
configurable "boot N times before giving up" counter.
[`PV_REVISION_RETRIES`](/pantavisor/reference/pantavisor-configuration)
(default `10`) is a separate, Pantavisor-side setting for revision-transition
retries — not a boot-attempt count.

> **📝 Note**
>
> This page ships with measured results and the rig design as part of hardening
> the trust story. Until then it documents the guarantee and methodology.
