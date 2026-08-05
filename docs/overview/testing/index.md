---
title: "Testing"
description: "Automated pvtest suite and manual test workflows for meta-pantavisor and the Pantavisor runtime."
sidebar_position: 14
---

# Testing

Two distinct worlds, split accordingly:

## [Automated](automated/index.md) — the pvtest suite

One suite, driven by `test.docker.sh`, running against an appengine container, a pool of
them, or a real device.

1. [The pvtest Harness](automated/index.md) — architecture, execution models, execution
   flow, how to build and install it, and where a run's output lands
2. [Running and Authoring pvtests](automated/appengine.md) — running against the appengine
   pool, adding and updating tests and containers, the authoring rules (including the
   cross-target ones), and how CI drives it
3. [Running Against a Real Device](automated/device.md) — the device manifest, the re-type
   hook, substituting container tarballs for another architecture or signing CA, and which
   non-PASS results are expected
4. [pvtest List](automated/pvtest-list.md) — every test by scope and category, with status

## [Manual](manual/index.md) — hand-driven testing

Building and loading the appengine image, plus the per-feature
[test plans](manual/testplans/index.md) (auto-recovery, cgroups, container control, IPAM,
pvctrl, pvtx, xconnect).

Driving the appengine container itself — starting it, entering namespaces, log locations,
`pvcurl`/`pvcontrol` recipes — is documented in the pantavisor repo at
`docs/overview/appengine.md`, alongside the `pv-appengine` code.

## Keeping the test list updated

When a pvtest is added, modified, or removed, update
[automated/pvtest-list.md](automated/pvtest-list.md) and `TODO.md`. Mark completed tests `✓`.
