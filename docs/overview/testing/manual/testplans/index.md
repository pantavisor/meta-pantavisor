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
8. [Remote Update Cancel](testplan-remote-cancel.md) — owner cancel from the Hub honored while queued or downloading
9. [Object Download Resume](testplan-object-download-resume.md) — HTTP Range-based resume of interrupted OTA object downloads
10. [Download Progress](testplan-download-progress.md) — continuous mid-object OTA download-progress reporting, local and on the Hub

## Writing a test plan

A test plan is a procedure a person follows at a terminal. Write it so that
someone who has never seen the feature can run it top to bottom and decide
pass or fail at each step. Use
[testplan-object-download-resume.md](testplan-object-download-resume.md) as the
template. The shape:

1. **Title and two or three sentences** saying what the feature does and what
   changed. Then a `**Scope**:` line naming the setup the plan needs (an
   appengine, a claimed device, a Hub).
2. **Automated Coverage**: which pvtest covers which of the numbered tests,
   with a table mapping each test to the marker lines in its golden `output`.
   Name what is not automated and why.
3. **Prerequisites**: the exact commands to bring the setup into place,
   labelled "on the device" or "on the workstation", plus the teardown. Put
   values the reader must substitute in angle brackets: `<rev>`, `<sha>`,
   `<nick>`.
4. **Numbered tests**, each with an `### Execute` block holding the commands
   and an `### Expected` block holding what the output must show. One thing
   per test. If a check can only be done by hand, mark the test "(manual
   only)" and say what it needs.

Keep out of the plan: design rationale, the history of how the test was
arrived at, bugs found along the way, environment problems of one
workstation, and copies of the test script or its `test.json`. The pvtest
source is the reference for those, and the automated coverage table links
the two. Explanations belong in the feature's own documentation.

Every command, key, path and log line in a plan must exist. Check them
against the source or run them before writing them down.

Create the plan as `testplan-<feature>.md` in this directory, add it to the
list above and to the table in [manual/index.md](../index.md), and add the
covering pvtest to
[pvtest-list.md](../../automated/pvtest-list.md).
