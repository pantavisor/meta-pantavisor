---
title: Trust model
sidebar_position: 2
description: Pantavisor's trust model — what it protects, the trust boundaries from secure boot to per-container integrity, and why owning PID 1 raises the bar rather than lowering it.
---

# Trust model

Pantavisor owns PID 1 — the kernel's first, always-running process, normally
`init`/`systemd` — so it must clear a higher bar than an updater you can
delete. This page describes what Pantavisor protects, the trust boundaries
involved, and how the pieces compose into a chain from power-on to a running
container. For the power-fail evidence behind the atomicity claims, see
[Atomicity and trust evidence](/meta-pantavisor/getting-started/security/atomicity-and-trust).

## What Pantavisor protects

- **Integrity of the device state** — the kernel, BSP, every container, and
  configuration are described as content-addressed objects under one signed
  revision. Tampering with any object changes its hash and breaks the signature.
- **Integrity at runtime** — container root filesystems are verified as they are
  mounted, not only at download time.
- **Confidentiality of stored state** — the storage partition can be encrypted.
- **Recoverability** — a revision that fails its health checks is rolled back
  automatically to the last known-good state.

## Trust boundaries

| Boundary | Mechanism | Notes |
|---|---|---|
| Power-on → bootloader | Secure boot (SoC ROM verifies a signed bootloader) | Platform-dependent; see your board's secure-boot support. |
| Bootloader → kernel/initramfs | Signed FIT image | The bootloader only boots a signed image. |
| Initramfs → device state | Signed revision (`pvr sig`, X.509) | One signature transitively covers the whole revision. |
| Mount → running container | dm-verity | Per-container rootfs integrity is checked at mount time. |
| Storage at rest | dm-crypt | Encryption of the storage partition (dm-crypt). |
| Update commit | Health-gated commit + bootloader try/rollback | A trial revision must pass readiness probes before it is marked good. |
| Liveness backstop | Hardware watchdog fed by PID 1 | If Pantavisor stops feeding it, the device resets. |

## The chain, end to end

```
SoC ROM
  └─ verifies → signed bootloader
       └─ verifies → signed FIT (kernel + Pantavisor initramfs)
            └─ Pantavisor (PID 1) verifies → signed revision
                 └─ mounts each container rootfs under → dm-verity
                      └─ (storage partition encrypted with dm-crypt)
```

Each link only hands control to the next if the next artifact verifies. A break
anywhere stops the boot or triggers rollback rather than running unverified
code.

## Why PID 1 raises the bar, not lowers it

A conventional updater is a process you can stop, replace, or remove — its
guarantees end where the surrounding OS begins. Because Pantavisor *is* the init
system and the update path, its atomicity and rollback guarantees apply to the
**whole device**, including the base and kernel, and they are held to a higher
standard precisely because there is no layer underneath to fall back on. That is
why the trust story is backed by a documented, reproducible
[power-fail and rollback test methodology](/meta-pantavisor/getting-started/security/atomicity-and-trust)
(results forthcoming) rather than assertion alone.

## The recertification advantage

Because an application update changes only its own container's objects — never
the certified base container's hashes — a frozen, certified base/BSP keeps its
safety case while apps iterate above it. This is the core of the
[recertification model](/meta-pantavisor/getting-started/security): certify the base once, ship app containers
without re-touching it.

> **📝 Note**
>
> Secure boot specifics (key provisioning, FIT signing, fuse burning) are
> platform-dependent. Treat your board's reference material and the
> [build/secure-boot integration](/meta-pantavisor/overview/get-started) guidance as authoritative for your SoC.
