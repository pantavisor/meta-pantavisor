# Wakelock cadence — kernel enablement (parked)

This branch parks the kernel-side enablement for **phase-1 declarative wakelock
cadence**, so it is ready to pick up when the cadence work itself lands. It is
not part of meta-pantavisor#422 (wakelock/managed BSP enablement) on purpose —
see "Why this is not in #422" below.

## What cadence is

Containers declare their own wake cadence instead of Pantavisor waking on a
single global interval. Pantavisor opens a **wake window** per declared
cadence, coalesces requests within 25% so a 2-minute container interval rides
an existing 60s heartbeat wake rather than adding its own, and closes the
window early once the container has actually gone idle.

The runtime lives on the pantavisor branch `feature/wakelock-cadence`
(`power/cadence.c`, scheduler + quiescence in `power/wakelock.c`). As of
2026-08-10 that branch has **no open PR** — it was device-validated on
2026-07-23 on `labslave_var-som-mx8mn` rev128 (90+ min healthy ~120s
suspend/resume, 20 window opens / 19 closes all `reason=quiesce`).

## What is here

`wakelock-psi.cfg` — `CONFIG_PSI=y`, wired into `linux-%.bbappend` behind a
`PANTAVISOR_FEATURES` check for `wakelock-cadence`. That is a second gate on
top of `wakelocks` (which #422 gates the base fragment on): cadence needs both,
since PSI is useless without the wakelock/autosleep machinery underneath.
Nothing enforces the pairing in the recipe — enabling `wakelock-cadence`
without `wakelocks` silently yields PSI and no wakelocks. Worth an assertion if
this grows.

## Why PSI, and why it is optional

The quiescence detector (`_window_is_quiescent()`) reads per-cgroup
`cpu.pressure` to distinguish a container that is genuinely idle from one that
is runnable but starved of CPU, and closes a wake window early only for the
former. It degrades through an explicit ladder:

    per-cgroup cpu.pressure (unified mount)
      -> global /proc/pressure/cpu as a stall veto + per-cgroup usage
        -> usage-only

When PSI is absent `psi_ok` is false, the stall veto never fires, and the
decision falls through to `cpu.stat` usage. Cadence still works — it just
loses the veto, so a stalled container can look idle by usage alone and get
its window closed early. Worst case a window runs to `max_awake`.

## Why this is not in #422

`CONFIG_PSI` accounting is always-on once compiled in (`CONFIG_PSI_DEFAULT_DISABLED`
is a separate option, unset). Carrying it in #422's common fragment would charge
every device that opts into wakelocks the overhead for a consumer that is not
merged and, per the ladder above, does not even require the symbol. Hence the
separate opt-in fragment, matching how `squash-lz4` / `caam-nxp` / `dcp` are
gated in the same file.

(Historically this mattered more: #422's fragment was applied to *every*
pantavisor kernel, gated only on `DISTRO_FEATURES` `pantavisor-system` /
`pantavisor-kernel`. #422 now gates it on the `wakelocks` feature too, so the
blast radius of either symbol is opt-in.)

## To pick this up

1. Rebase onto whatever #422 became (this branch is based on its SNVS commit).
2. Open the pantavisor cadence PR from `feature/wakelock-cadence`.
3. Decide whether `wakelock-cadence` should be a default in
   `classes/pvbase.bbclass:PANTAVISOR_FEATURES` or stay opt-in per build config.
   It is deliberately **not** a default here.
4. Verify `CONFIG_PSI=y` reaches the final `.config` with the feature enabled
   and is absent without it. Nothing on this branch has been build-tested.

## Open questions from the cadence validation

- `CONFIG_PSI_DEFAULT_DISABLED` unchecked — may need `psi=1` on the cmdline.
- cgroup-v2-in-hybrid per-container path unverified on device.
- Window registry only refreshed at managed-ready / mode transition (no updater
  hook after revision changes).
