---
title: Secure OTA updates
sidebar_position: 3
description: Secure embedded Linux OTA with Pantavisor — content-addressed object integrity, PVS signatures over the state JSON, x5c certificate chains, replay defense, and a tamper-evident trail.
---

# Secure OTA updates for embedded Linux

## The threat model

An OTA channel is an attractive attack surface: compromise the update path and
you compromise every device. A serious design must defend against:

1. **Tampering in transit** — the payload is modified between server and device.
2. **Compromised registries** — a Docker tag is repointed to a malicious image.
3. **Insider compromise of the update server** — an unsigned but valid-looking state is pushed.
4. **Replay attacks** — an old, vulnerable revision is replayed onto a device.
5. **Trust bootstrap** — devices must know which keys to trust without phoning home for each update.

Pantavisor addresses these through **content-addressed state + PVS signatures +
verified boot integration**.

## Layer 1 — content addressing (integrity)

Every binary object in a Pantavisor state is referenced by SHA256 hash. The state
JSON is a flat list of `(path, hash)` pairs for binaries plus inlined JSON:

```json
{
  "bsp/kernel.img": "4186c915bc30071a1395fbe6ebe81e328fc9b9ee88d6c5af7d27291b20afcf89",
  "os/root.squashfs": "dffbfec7c077a5ab06737f2cec9917bae6dedb39b9151172e42c2a22a2a36475"
}
```

To tamper with an object you'd need a SHA-256 second-preimage attack. Differential transfer
(only changed hashes) doesn't weaken integrity — every object's hash is checked
on the device after fetch.

## Layer 2 — PVS signatures (authenticity)

Content addressing proves *integrity* (the bytes weren't tampered with). It does
not prove *authenticity* (the state came from someone authorized). For that, sign
the state with **PVS** (`pvs@2` signatures over the state JSON):

```bash
# Sign a part of the state (repeat for each part you ship)
pvr sig add --part os
pvr sig add --part bsp
pvr sig add --part wificonnect

# Sign without including overlay config in the signature
pvr sig add --noconfig --part myapp

# List signatures
pvr sig ls

# Update existing signatures after changing the parts they cover
pvr sig update
```

A PVS signature covers the state JSON and therefore, transitively, every object
hash it references. Devices configured for signature verification reject unsigned
or wrongly-signed states.

## Layer 3 — x5c certificate chains (trust)

For production fleets you don't want to ship raw public keys to every device. A
PVS signature can carry an **x5c certificate chain** in its protected header (see
the [signature manifest](/pantavisor/reference/pantavisor-state-format-v2)),
so devices verify the signature against a trust root (typically your CA). This
decouples key rotation from device firmware: rotate signing keys, issue new certs
from the same CA, and devices keep accepting updates without a re-flash.

## Layer 4 — sign-then-push workflow

Production-safe OTA:

```bash
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME ws
cd ws

# ... modify containers, configs ...

# Sign each part that ships (signature files are created untracked)
pvr sig add --part os
pvr sig add --part bsp

# Stage everything — including the new signatures — then commit and push
pvr add .
pvr commit -m "Security update"
pvr post https://pvr.pantahub.com/USERNAME/DEVICE_NAME
```

Sign *before* `pvr add .` and `pvr commit` — `pvr sig add` leaves the signature
files untracked, so committing first would post an unsigned state. The device
verifies signatures against its baked-in trust root before applying.

## Layer 5 — audit trail (non-repudiation)

Every `pvr post` produces an immutable trail step in Pantahub. The step records
the state JSON (with object hashes), the signatures applied, and the timestamp
and authenticated user/token that posted it. For compliance you can prove **what
was deployed, when, by whom, and that it was authentic** — months or years later.

## Layer 6 — verified boot (defense in depth)

For maximum assurance, combine Pantavisor signatures with platform verified boot:

- **Bootloader** verifies the kernel + initramfs (board-specific — UEFI Secure Boot, U-Boot FIT signing, RPi sign-tool).
- **Pantavisor** verifies the state JSON signatures.
- **Container rootfs** uses **dm-verity** so even runtime tampering is detected.

Each layer enforces its own integrity check; compromise requires breaking all of
them. See the [trust model](/meta-pantavisor/getting-started/security/trust-model) for the full chain.

## Defending against replay

Pantavisor doesn't blindly accept any signed state — the device tracks the
current trail step and only applies updates targeted at it. Within the
Pantahub-managed flow, re-posting an old revision requires a **new, logged post**
that appears in the audit trail. Note that Pantavisor itself does not maintain an
anti-rollback counter, so protect local access to the device accordingly.

## Defending against compromised sources

When wrapping Docker images as containers, **pin by digest, not tag**:

```bitbake
# Bad — mutable
PVR_DOCKER_REF = "alpine:latest"

# Good — immutable
PVR_DOCKER_REF = "alpine@sha256:21a3deaa0d32a8057914f36584b5288d2e5ecc984380bc0118285c70fa8c9300"
```

The state hash now anchors the exact image bytes; even if the registry is
compromised and the tag repointed, the next build fails the hash check.

## Self-hosting for sovereignty

The public Pantahub is convenient for development. For production with strict
data-sovereignty or air-gapped requirements, self-host Pantahub — it is fully
open source — and bake your own CA into devices. No third party sits between your
sign step and your fleet.

## Common pitfalls

- **Skipping `pvr sig add`** — content addressing without signatures defends
  against tampering but not against malicious sources.
- **Signing only some parts** — unsigned parts of the state are unverified. Sign
  everything that ships.
- **Forgetting key rotation** — plan an x5c certificate chain into the design from
  day one so you can rotate without re-flashing.

## Next steps

- [Trust model](/meta-pantavisor/getting-started/security/trust-model) — the end-to-end verification chain
- [Security and compliance](/meta-pantavisor/getting-started/security) — signed revisions, dm-verity, dm-crypt
- [Reproducible builds](/meta-pantavisor/getting-started/solutions/reproducible-builds) — reproducibility complements signed integrity
