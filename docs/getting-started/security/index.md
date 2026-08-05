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
  integrity, [PVS signatures](/pantavisor/reference/pantavisor-state-format-v2#9-security-_sigscontainerjson)
  over the state JSON, [x5c](https://www.rfc-editor.org/rfc/rfc7515#section-4.1.6)
  (JOSE/JWS) certificate chains, and the tamper-evident audit trail.

## Runtime reference

The trust/signing model these pages describe is built on primitives defined
on the `pantavisor/` side, not repeated here:

- [Revisions](/pantavisor/overview/revisions) — what a revision actually is
  (the unit every signature covers).
- [Objects and storage](/pantavisor/overview/storage) — the "Integrity"
  section has the full signing scheme: algorithms, verification points, and
  the `disabled`/`audit`/`lenient`/`strict` severity levels. **Read this
  before concluding signing is optional** — the state-format reference
  marks the signature manifest "Mandatory: No" because validation strictness
  is configurable, not because unsigned states are always accepted;
  `lenient` (the default) still fails a revision whose signature doesn't
  validate once present, and `strict` requires one.
- [Claiming a device](/meta-pantavisor/getting-started/operate/device-access/remote-pantahub) —
  the registration/claim flow that binds a device to a Pantahub account.
- [`pvr sig`](/meta-pantavisor/getting-started/develop/cli-tools/pvr-cli#signing-a-revision) —
  signing commands and key flags.

## Planned coverage

Future pages will cover secret handling, SBOM generation and the CVE/update
workflow, the recertification model (a frozen, certified base/BSP plus app-only
container updates that preserve the safety case), Cyber Resilience Act
readiness, and IEC 62304 / IEC 62443 positioning.
