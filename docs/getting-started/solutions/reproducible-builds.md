---
title: Reproducible builds
sidebar_position: 2
description: Pantavisor delivers bit-exact recovery of any deployed state through content-addressed state revisions — every state JSON is hashed over its objects, so re-cloning a historical revision yields byte-identical artifacts.
---

# Reproducible embedded Linux builds

## The problem

Embedded Linux builds drift. The same `bitbake` invocation today and a year from
now can produce subtly different artifacts: package versions move, mirror
tarballs change, build hosts differ. For compliance audits, security forensics,
regulatory submissions, and post-incident debugging, you need to **recover the
exact firmware that was running on a specific device at a specific moment** — bit
for bit.

Yocto and Buildroot offer reproducible *rebuilds* if you pin everything
carefully. Pantavisor attacks the problem from the other end: every deployed
state is content-addressed and immutable, so you can **recover any revision a
device ever ran, bit for bit, without rebuilding anything**.

## How Pantavisor achieves bit-exact recovery

### Content-addressed state

A Pantavisor state is a single JSON document. Inside it, JSON files are inlined
verbatim and binary files are referenced by SHA256 hash:

```json
{
  "#spec": "pantavisor-service-system@1",
  "bsp/kernel.img": "4186c915bc30071a1395fbe6ebe81e328fc9b9ee88d6c5af7d27291b20afcf89",
  "bsp/modules.squashfs": "7bb6ce5913ad5c14e14537d552ad0fba7952011e9135f724f9c38baee9b76e53",
  "os/root.squashfs": "dffbfec7c077a5ab06737f2cec9917bae6dedb39b9151172e42c2a22a2a36475"
}
```

Two states with the same JSON have the same hashes, and the same hashes resolve
to the same bytes in the object store. **There is no name-to-version
indirection** — no "latest" tag, no mutable label. The hash *is* the identity.

### Immutable trail steps

Every `pvr commit` + `pvr post` produces a numbered trail step in Pantahub. Each
step is permanent and content-addressed. Re-cloning a step produces
byte-identical artifacts (as long as Pantahub still hosts the objects):

```bash
# Recover the exact firmware deployed to this device
pvr clone https://pvr.pantahub.com/USERNAME/DEVICE_NAME audit-ws
```

then check out the historical step you need — see the Pantahub documentation for
how to address a specific revision. The resulting workspace is bit-identical to
what the device booted.

## What this buys you

- **Compliance and audit** — regulated industries (medical, automotive,
  industrial) can prove which firmware was running on which device and when, with
  an unforgeable content-addressed record.
- **Forensics** — clone the exact revision a device was running, bring it up in a
  lab, and reproduce the failure. No "we *think* it had this build."
- **Bisecting failures** — every step is recoverable in full fidelity; bisect the
  way you bisect git commits.
- **CI/CD verification** — hash CI artifacts and compare against the state JSON
  about to be promoted; a mismatch fails the pipeline.

## Reproducibility beyond Pantavisor

Pantavisor guarantees reproducibility of the *state* (what's deployed). For
end-to-end reproducibility you also need deterministic *build inputs*:

1. **Pin Yocto layers** with explicit revisions in `bblayers.conf` and KAS YAML.
2. **Pin Docker source images** by digest (`@sha256:...`) when wrapping them.
3. **Use signed source mirrors** in Yocto (`SOURCE_MIRROR_URL` + checksums).
4. **Build in a pinned container** (`kas-container`) to remove host-OS variance.
5. **Sign the resulting state** with `pvr sig add` so tampering is detectable.

## How this compares

| System | State immutability | Object dedup | Auditable history |
|---|---|---|---|
| Yocto / Buildroot alone | Pin everything yourself | None | Build logs only |
| Docker / Balena | Image tag (mutable!) | Layer-level | Image digests if used |
| Pantavisor | SHA256 over state JSON | Object-level | Trail steps in Pantahub |

Docker tags are mutable by default; Pantavisor state hashes are not — there's no
tag, only the hash.

## Common pitfalls

- **Garbage-collecting Pantahub objects** gains storage but loses historical
  reproducibility — don't do it on production fleets without a retention policy.
- **Pinning Docker tags instead of digests** when wrapping images — tags drift,
  digests don't.
- **Forgetting to sign** — a state without `pvr sig add` is content-addressed but
  not authenticated.

## Next steps

- [Secure OTA updates](/meta-pantavisor/getting-started/solutions/secure-ota) — add PVS signatures on top of reproducibility
- [Operate devices](/meta-pantavisor/getting-started/operate) — roll back to any historical revision
- [Configuration](/meta-pantavisor/getting-started/develop/cli-tools/configuration) — how the state JSON is structured
