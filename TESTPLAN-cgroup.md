# TESTPLAN-cgroup

Validation for pantavisor's cgroup handling on HYBRID-mode devices (embedded/standalone init), covering both lenient-stop and force-stop (SIGKILL) container lifecycle paths.

## Scope

- Verify cgroup version detection reports `CGROUP_HYBRID` on devices that mount v1 controllers plus a v2 unified tree at `/sys/fs/cgroup/unified/`.
- Verify `pv_cgroup_destroy()` cleans every v1 controller hierarchy plus the unified tree, removing both `lxc/<name>/` and `lxc.monitor.<name>[-N]/` leaves.
- Verify no `-N` suffix accumulation on monitor cgroups across repeated stop/start cycles.
- Verify behaviour on both lenient-stop (container handles SIGPWR) and force-stop (container ignores signals).

## Test containers

Two minimal `inherit image` containers (~700 KB each) in `recipes-containers/pv-examples/`:

| Container | Script | Behaviour |
|-----------|--------|-----------|
| `pv-example-app` | `pv-app.sh` — traps `TERM PWR INT`, `exit 0` | Exits on LXC's lenient signal → no force_stop → LXC cleans cgroups itself |
| `pv-example-stubborn` | `pv-stubborn.sh` — `trap '' TERM PWR INT HUP QUIT USR1 USR2` | Ignores all catchable signals → pantavisor's `lenient-stop` timer expires → `pv_platform_force_stop()` SIGKILLs init → `pv_cgroup_destroy()` cleans cgroups |

Both have `PV_RESTART_POLICY=container` so they can be driven by the `pv-ctrl` container lifecycle API.

## Prerequisites

- Device deployed with a pantavisor build carrying the three commits on `fix/cgroup-destroy-all-init-modes` (PR #688).
- Both example containers installed.
- SSH or tailscale access to the device.

Confirm detection first:
```sh
grep "cgroup version" /storage/logs/<rev>/pantavisor/pantavisor.log | tail -1
# expect: cgroup version detected 'CGROUP_HYBRID'
```

## Baseline check

After boot, each container's cgroup leaves are present across all hierarchies:
```sh
find /sys/fs/cgroup/ -maxdepth 3 \
    \( -name "pv-example-app" -path "*/lxc/*" \
       -o -name "lxc.monitor.pv-example-app*" \) \
    | sort
```
Expected: 26 entries on a typical HYBRID device (13 hierarchies × 2 patterns each) — all without `-N` suffix.

## Test 1 — lenient stop path

```sh
pvcontrol containers stop pv-example-app
# wait for STOPPED status
# then:
find /sys/fs/cgroup/ -maxdepth 3 \
    \( -name "pv-example-app" -path "*/lxc/*" \
       -o -name "lxc.monitor.pv-example-app*" \) \
    | wc -l
```
**Expected:**
- `STOPPED` reached in ~3 s (no 30 s force_stop timeout).
- Log: `platform 'pv-example-app' exited during lenient stop`.
- Zero leaves after STOPPED state.

## Test 2 — force stop path (SIGKILL)

```sh
pvcontrol containers stop pv-example-stubborn
# wait for STOPPED status
# then the find command above for pv-example-stubborn
```
**Expected:**
- `STOPPED` reached in ~6-10 s (after lenient-stop timer expires).
- Log: `platform 'pv-example-stubborn' did not exit after lenient stop, force stopping`.
- Log: `pv_platform_force_stop: force stopping platform 'pv-example-stubborn'`.
- Log: one or more `pv_cgroup_remove_retry: ... still exists. Removing...` entries.
- Zero leaves after STOPPED state (pantavisor's cleanup ran).

## Test 3 — repeated cycles, no -N accumulation

For each container run 3 stop/start cycles:
```sh
for K in 1 2 3; do
    pvcontrol containers stop <name>
    # wait STOPPED
    pvcontrol containers start <name>
    # wait STARTED
    # check no suffix
    find /sys/fs/cgroup/ -maxdepth 3 -name "lxc.monitor.<name>-*"
done
```
**Expected:**
- Every `find` for `lxc.monitor.<name>-*` returns empty.
- Container always starts with the base name `lxc.monitor.<name>` (no suffix).

## Manual inspection on failure

If dirt is observed, dump state across all hierarchies:
```sh
for h in /sys/fs/cgroup/*/; do
    ls -d ${h}lxc.monitor.<name>* ${h}lxc/<name> 2>/dev/null
done
```
And check pantavisor log for the relevant cgroup cleanup entries:
```sh
grep -E "pv_cgroup|cgroup_remove" /storage/logs/<rev>/pantavisor/pantavisor.log
```

## Known gotchas

- **Status must fully reach STOPPED**: issuing `start` while the container is still `STOPPING` replaces the callback with `restart`, masking the test. Always wait for `STOPPED`.
- **Busybox shell minimal toolset**: no `seq`, `wc` — use `while`/`$((i+1))` loops instead.
- **Container must have `PV_RESTART_POLICY=container`**: system-policy containers cannot be driven by the lifecycle API.

## Reference

- PR: https://github.com/pantavisor/pantavisor/pull/688
- LXC cgroup layout detection: `src/lxc/cgroups/cgfsng.c:2940` `cg_hybrid_init`
- LXC monitor idx retry logic: `src/lxc/cgroups/cgfsng.c:1235` `cgfsng_monitor_create`
