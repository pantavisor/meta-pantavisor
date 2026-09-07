---
title: "Testing"
description: "Automated pvtest suite and manual test workflows for meta-pantavisor and the Pantavisor runtime."
sidebar_position: 14
---

# Testing

Two distinct worlds, split accordingly:

## [Automated](automated/index.md) — the pvtest suite

The suite itself lives in the **pantavisor** repo, which documents it:
[Testing](../../../pantavisor/testing/index.md) — the harness architecture, running it against
the appengine pool or a real device, authoring tests, and the test list.

This repo only assembles the distro that runs it, so what stays here is the build:
[Building the pvtest distro](automated/index.md) — the tarball, the fixture containers, and the
pantavisor pin (`PANTAVISOR_SRCREV`).

## [Manual](manual/index.md) — hand-driven testing

Building and loading the appengine image, plus the per-feature
[test plans](manual/testplans/index.md) (auto-recovery, cgroups, container control, IPAM,
pvctrl, pvtx, xconnect).

Driving the appengine container itself — starting it, entering namespaces, log locations,
`pvcurl`/`pvcontrol` recipes — is documented in the pantavisor repo at
`docs/overview/appengine.md`, alongside the `pv-appengine` code.

## Keeping the test list updated

When a pvtest is added, modified, or removed, update the list in the pantavisor repo
([pvtest-list.md](../../../pantavisor/testing/pvtest-list.md)) and `TODO.md`. Mark completed
tests `✓`.
