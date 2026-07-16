---
title: Reduce firmware size
sidebar_position: 1
description: Pantavisor's runtime is a ~1 MB binary running as PID 1 — no daemon, no image cache, flexible storage backends — so you get containers, OTA, and rollback without a large footprint.
---

# Reduce embedded Linux firmware size

## The problem

Embedded Linux footprint matters: cellular IoT devices ship with tens of MB of
flash, industrial gateways are quoted in hundreds of MB, and every megabyte is
bandwidth, cost, and update window. Most container runtimes built for cloud
(Docker + containerd, even k3s) sit at tens-to-hundreds of MB just for the engine
— before any application code.

## Pantavisor's footprint

Pantavisor itself is a **single ~1 MB binary** that runs as PID 1. There is:

- **No container daemon** — no `dockerd`, no `containerd`. Each LXC container is a normal supervised process tree.
- **No image cache** — content-addressed objects are stored once in `objects/`, referenced by hash from any state revision.
- **No mandatory overlay layer cache** — Docker defaults to overlayfs and assumes ample writable-layer storage; Pantavisor doesn't.

A realistic minimal Pantavisor system:

| Component | Approx. size |
|---|---|
| Pantavisor (PID 1) | ~1 MB |
| LXC + supporting binaries | ~3–5 MB |
| Kernel + initramfs (varies by board) | 5–15 MB |
| Minimal BSP container (Alpine + ConnMan style) | 8–20 MB |
| Per-app container (typical) | 5–30 MB |

The runtime itself stays around a megabyte, and squashfs container volumes are
typically 50–70% smaller than a plain rootfs. Total image size then depends on
which factory containers you bundle — the default CI starter images bundle
several factory containers and are correspondingly larger (a few hundred MB
compressed).

## Why it stays small

1. **No long-running daemon.** `dockerd` is a privileged root daemon that idles
   at significant RAM and disk. Pantavisor *is* PID 1; no separate process owns
   container lifecycle.
2. **Content-addressed object store.** Every file (kernel image, container
   rootfs, config blob) is stored by its SHA256 hash. Two containers sharing the
   same library share the same object; two revisions sharing 99% of their content
   share 99% of objects.
3. **Flexible storage backends.** Containers can use squashfs (read-only,
   compressed), dm-verity (verified read-only), raw block volumes, or overlayfs —
   only when you actually want it.
4. **Differential OTA.** Updates ship only changed object hashes; a 200 KB config
   tweak doesn't push a 200 MB rootfs over cellular.
5. **Kernel and BSP as containers.** Kernel + modules + firmware live inside a
   `bsp/` container sharing the same object store — no separate system partition
   duplicating storage.

## Practical footprint-reduction tips

1. **Use squashfs root volumes** in your container recipes for a 50–70% size
   reduction vs a plain rootfs.
2. **Strip the BSP** — disable kernel features you don't use;
   [`PANTAVISOR_FEATURES`](/meta-pantavisor/overview/build-system#pantavisor_features) toggles what's compiled in.
3. **Share base layers across containers** — use the `--base` flag with
   `pvr app add` to create overlay containers that diff against a shared base.
4. **Ship only what every unit needs** — containers listed in
   `PVROOT_CONTAINERS_CORE` and `PVROOT_CONTAINERS` are both deployed into the
   image. The saving comes from leaving optional apps out of the factory image
   entirely and installing them later over OTA.
5. **Compress on transfer** — `pvflasher` accepts `.bz2`, `.xz`, `.zst`, and
   `.gz` directly; ship images compressed and decompress on the device.

## Trade-offs to be aware of

- **System containers are larger than Docker app containers** by design — they
  include init and supporting userspace. The overall *system* is smaller, but a
  single Pantavisor container is usually larger than a single Docker app container.
- **Kernel-as-container adds the BSP container's overhead** — this buys you
  OTA-able kernels; pay it knowingly.

## Compared to alternatives

| Stack | Engine footprint | Notes |
|---|---|---|
| Docker on embedded | ~50–100 MB for `dockerd` + containerd | Plus image-cache growth |
| balenaEngine + balenaOS | ~80–200 MB host OS | Slimmed Docker, still daemon-based |
| Pantavisor + LXC | ~1 MB Pantavisor + small LXC | No daemon, content-addressed dedup |
| Buildroot alone | Smallest in class (single-digit MB) | But no container runtime, OTA, or fleet |

If raw minimalism is the only goal, [Buildroot](/meta-pantavisor/getting-started/benchmarks/vs-buildroot) still
wins. If you want minimal *plus* containers + OTA + rollback + fleet, Pantavisor
is the smallest stack that delivers that combination.

## Next steps

- [Reproducible builds](/meta-pantavisor/getting-started/solutions/reproducible-builds) — why content-addressed dedup also gives reproducibility
- [Build with Yocto](/meta-pantavisor/overview/get-started) — configure a slim image
- [Pantavisor vs Buildroot](/meta-pantavisor/getting-started/benchmarks/vs-buildroot) — where each wins
