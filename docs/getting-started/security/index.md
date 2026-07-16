---
title: Security and compliance
description: Trust model, signed revisions, secure boot, SBOM/CVE, and recertification.
sidebar_position: 8
---

# Security and compliance

Because Pantavisor owns PID 1, it is held to a higher trust bar than a deletable
updater — these pages spell out the trust model and how its guarantees are
tested.

## Pages

- **[Trust model](./trust-model.md)** — what Pantavisor protects, the trust
  boundaries from secure boot to per-container integrity, and the end-to-end
  verification chain.
- **[Atomicity and trust evidence](./atomicity-and-trust.md)** — a documented,
  reproducible power-fail and rollback test methodology (results forthcoming).
- **[Secure OTA updates](/meta-pantavisor/getting-started/solutions/secure-ota)** — content-addressed object
  integrity, PVS signatures over the state JSON, x5c certificate chains, and the
  tamper-evident audit trail.

## Planned coverage

Future pages will cover secret handling, SBOM generation and the CVE/update
workflow, the recertification model (a frozen, certified base/BSP plus app-only
container updates that preserve the safety case), Cyber Resilience Act
readiness, and IEC 62304 / IEC 62443 positioning.
