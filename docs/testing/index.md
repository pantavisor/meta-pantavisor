---
title: "Testing"
description: "Development and automated test workflows for meta-pantavisor and the Pantavisor runtime."
sidebar_position: 5
---

# Testing

Test workflows for iterating on meta-pantavisor changes and running structured pvtest suites.

## Topics

1. [Development Workflow](development-workflow.md) — manual iteration during development: run appengine locally, use `pvcurl`/`pvcontrol` inside containers, and verify behavior before CI
2. [Automated Workflow](automated-workflow.md) — structured testing with `test.docker.sh`: valgrind, CI validation, force-clean rebuilds, and the pvtest todo list
3. [Test Plans](testplans/) — per-feature test plans covering auto-recovery, cgroups, container control, IPAM, pvctrl, pvtx, and xconnect

## Keeping the Todo List Updated

When a pvtest is added, modified, or removed, update the `pvtest todo list` in [automated-workflow.md](automated-workflow.md). Mark completed tests `✓`.
