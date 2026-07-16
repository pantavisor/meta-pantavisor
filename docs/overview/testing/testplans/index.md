---
title: "Test Plans"
description: "Structured test plans for Pantavisor runtime features tested via the pvtest suite."
sidebar_position: 3
---

# Test Plans

Structured test plans for each feature area covered by the pvtest suite. Each plan lists the tests, expected behavior, and pass/fail criteria.

## Plans

1. [Auto-Recovery](testplan-auto-recovery.md) — container and system auto-recovery after failures
2. [Cgroups](testplan-cgroup.md) — cgroup resource limits and enforcement
3. [Container Control](testplan-container-control.md) — start, stop, and lifecycle management via pvcontrol
4. [IPAM](testplan-ipam.md) — IP address management for xconnect-connected containers
5. [pvctrl](testplan-pvctrl.md) — pvcontrol API behavior: state queries, revision control, and boot success
6. [pvtx](testplan-pvtx.md) — pvtx.d boot-time init script execution and idempotency
7. [xconnect](testplan-xconnect.md) — service mesh proxy: Unix socket, REST, D-Bus, DRM, and Wayland

## Adding a New Test Plan

Create a new `testplan-<feature>.md` in this directory and add it to [automated-workflow.md](../automated-workflow.md)'s todo list.
