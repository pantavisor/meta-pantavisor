---
title: "Wakelocks: Orange Pi 3 LTS (crust)"
description: "Staged hardware test plan for real suspend-to-RAM on Orange Pi 3 LTS (H6) via crust SCP firmware, validating pantavisor's managed wakelock mode."
sidebar_position: 8
---

# Wakelocks: Orange Pi 3 LTS (crust)

Manual hardware test plan, **not** a pvtest — suspend-to-RAM needs real hardware
(serial console + power-cycle capability), which the pvtest harness does not model.
See `docs/overview/wakelocks.md` in the **pantavisor** repo (PR pantavisor#768) for
the `power.mode` states this validates, and the platform-agnostic wakelock testplan
landing alongside PR meta-pantavisor#422 for the non-crust-specific test matrix.

## Why this exists

meta-sunxi builds U-Boot for all sun50i boards with `SCP=/dev/null` (no SCP
firmware). On ARISC-bearing Allwinner SoCs (H6 included), deep suspend
(PSCI `SYSTEM_SUSPEND`) is implemented by firmware running on that core — without
it, TF-A falls back to a native PSCI backend that offers no deep-sleep state on H6,
and Linux is limited to s2idle. `recipes-bsp/crust` builds the
[crust](https://github.com/crust-firmware/crust) SCP firmware and wires it into
U-Boot for `orange-pi-3lts` only, so this board gains real suspend-to-RAM and can
be used to validate pantavisor's `power.mode=managed` autosleep loop.

## Prerequisites

- Machine: `orange-pi-3lts`, built with this branch (crust in the boot chain).
- `power.mode=managed` requires PR pantavisor#768 + meta-pantavisor#422 (kernel
  `CONFIG_PM_WAKELOCKS`/`CONFIG_PM_AUTOSLEEP` fragment) merged or rebased in
  alongside this branch — Stage 0/1 below only need `CONFIG_SUSPEND`/`CONFIG_PM_SLEEP`,
  which are on by default; Stage 2/3 need the full wakelocks fragment too.

## Safety rules (non-negotiable — this board has wedged before on this campaign)

- All suspend testing happens with a **serial console attached** and a way to hard
  power-cycle (bench access or power rig). Never start suspend tests on a device
  that is tailscale/ssh-only.
- **NEVER** `echo mem > /sys/power/state` without an armed RTC wakealarm. An
  unwakeable suspend can require full power removal (discharge) to recover.
- While inspecting interactively over ssh with autosleep active, hold a manual
  lock: `echo pvtest > /sys/power/wake_lock` (release with `wake_unlock`) so the
  box doesn't suspend under you.
- Deploy risky BSPs as **tryboot** so a failed boot rolls back; keep the current
  known-good `locks`-mode revision as the rollback target.
- Device storage: never write into `/storage/trails/` or `/storage/objects/`; test
  files go under `/storage/`; deploys go through `pvr`.

**Objective suspend/wake signal:** continuous `ping` from another host (or a dut
container). Gaps = suspended; replies = awake. Serial console output stopping
during `mem` is expected and is **not** a failure indicator.

## Stage 0 — build + boot parity

Gate: no regression.

1. Build the crust-enabled BSP for `orange-pi-3lts`.
2. Flash/tryboot on the bench board.
3. Verify:
   - U-Boot log shows SCP firmware loaded (not "SCP not present").
   - Normal boot to pantavisor is unchanged; wifi (uwe5622) comes up; device
     reaches the Hub.

**Gate:** boots identically to the non-crust build. If not, fix before any
suspend attempt.

## Stage 1 — platform capability triage

Gate: deep suspend exists.

On the booted board:

1. `cat /sys/power/mem_sleep` → must offer `deep` (or check dmesg for
   `psci: SYSTEM_SUSPEND` support).
2. `ls /sys/class/rtc/`; `cat /sys/class/rtc/rtc0/{name,date,time}`;
   `cat /sys/class/rtc/rtc0/device/power/wakeup` → want `enabled` (enable if not).
3. RTC-armed suspend probe:
   ```
   echo 0 > /sys/class/rtc/rtc0/wakealarm
   echo +30 > /sys/class/rtc/rtc0/wakealarm
   echo mem > /sys/power/state
   ```
   Expect: ping gap ~30s, then resume, `suspend_stats/success` incremented, RTC
   advanced ~30s, ssh/wifi functional again.
4. Repeat 5× single-cycle, then 3× back-to-back with only ~5s awake between
   cycles (the pattern autosleep produces, and where wifi drivers tend to break).

**Gate:** 5/5 single + 3/3 rapid cycles resume with network intact. Wifi dead
after resume → investigate the `sprdwl_ng` (UWE5622) driver before proceeding; do
**not** move to autosleep with a driver that wedges the SoC.

## Stage 2 — pantavisor managed mode, bench

Gate: sustained autosleep.

Deploy a revision with `power.mode=managed`, short wake interval (30–60s), as
tryboot. Watch via ping + serial:

- Device autosleeps between Hub polls, RTC-wakes on schedule, checks in,
  re-suspends.
- Run ≥ 10 consecutive cycles; verify Hub check-ins happened on schedule
  (device-meta/log timestamps), `suspend_stats` matches, no wedge.
- Verify an OTA while managed: push a trivial update; `WL_UPDATE` must hold the
  device awake through download/install; update completes and commits.

**Gate:** 10+ clean cycles AND one OTA completing under managed. Any SoC wedge →
capture serial + `/storage/logs/<rev>/`, power-cycle, roll back to `locks`,
report findings.

## Stage 3 — soak

Gate: production confidence.

Overnight (≥ 8h) managed soak at a realistic wake interval (e.g. 5min): count
cycles, Hub check-in regularity, RTC drift across the night, UWE5622 driver
health (dmesg errors accumulating?).

**Gate:** zero manual interventions overnight.

## If it fails

Distinguish and report precisely **where** it failed:

- (a) build/integration
- (b) firmware handoff (no deep state offered)
- (c) resume hang at firmware level
- (d) resume OK but wifi driver dead
- (e) autosleep-loop instability

Each has a different next step; a raw "doesn't work" is not an acceptable
outcome. Partial success (e.g. suspend works but not wifi) is valuable —
document it.

## Results

_To be filled in during Stage 0–3 execution._

| Stage | Date | Result | Notes |
|-------|------|--------|-------|
| 0 | | | |
| 1 | | | |
| 2 | | | |
| 3 | | | |
