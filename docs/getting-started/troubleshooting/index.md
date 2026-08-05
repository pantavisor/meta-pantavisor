---
title: Troubleshooting
sidebar_position: 11
description: Troubleshooting guide for Pantavisor Linux. Find solutions to common issues, connectivity problems, and app management questions.
---

Find solutions to common issues with Pantavisor Linux devices, builds, and application management.

## Quick Diagnostics

All on-device diagnostics below assume the [serial console debug shell](/meta-pantavisor/getting-started/operate/device-access/serial-port):

```bash
# Check which containers are running
lxc-ls -f

# List containers: status, group, status goal, restart policy
pvcontrol ls

# Restart just one container
pvcontrol containers restart <name>

# Check Pantavisor runtime log
tail /pv/logs/<revision>/pantavisor/pantavisor.log

# Check a specific container's output
tail /pv/logs/<revision>/<container>/lxc/console.log

# Check Pantahub connectivity (look for pantahub.online / pantahub.state)
pvcontrol devmeta ls
```

`<revision>` above is the number `pvcontrol ls` (or the pvtx web UI's "Rev"
field) shows for the container you're checking.

`pvcontrol ls`'s `status` column is one of `INSTALLED`, `MOUNTED`, `BLOCKED`, `STARTING`, `STARTED`, `READY`, `RECOVERING`, `STOPPING`, `STOPPED` — see [Container status](/pantavisor/overview/containers#status) for what each means and which ones indicate a problem (`BLOCKED` and `RECOVERING` are the ones to look for). `status goal` is the target status a container needs to reach — see [Status goal](/pantavisor/overview/containers#status-goal).

### Disk full / low on space

```bash
# Reclaim space — this is the only safe way to free /storage manually.
# Do NOT hand-delete files under /storage: the running, updating, and
# last-good revisions are protected automatically, but only pvcontrol
# knows which files those are.
pvcontrol storage gc
```

Running these from inside a container (e.g. an SSH session into pvr-sdk)
instead? The `/pv/` tree is mounted at `/pantavisor/` there — e.g.
`/pantavisor/logs/<revision>/...`.

## Common Issues

### Device boot-loops after a deploy

**Symptom**: The device keeps rebooting after pushing a new revision.

**Diagnosis**: A container in the new revision is failing to start, so auto-recovery retries it; after the retries are exhausted Pantavisor rolls back to the last `DONE` revision. There's no single fixed retry count — it's per-container/group `auto_recovery` config (`max_retries`, default `0` = unlimited retries, `policy` default `no` = disabled unless configured; see the [Auto-Recovery Object reference](/pantavisor/reference/pantavisor-state-format-v2#auto-recovery-object)). Check the logs of the failed revision under `/pv/logs/<revision>/`.

**Fix**: No manual intervention is needed for recovery — the device returns to the last good revision on its own. Fix the failing container and deploy again.

### OTA update appears stuck

**Symptom**: Pantahub shows an update that never reaches `DONE`.

**Diagnosis**: Check the status the update is stuck in: `QUEUED` (device has not picked it up yet — is it online?), `DOWNLOADING` (objects still transferring — slow link or large objects), `INPROGRESS` (installing on the device), `TESTING` (new revision booted and being evaluated before it is committed).

**Fix**: Verify connectivity with `pvcontrol devmeta ls` and watch the on-device logs under `/pv/logs/<revision>/` to see where it stalls.

### Claiming the device on Pantahub fails

**Symptom**: Entering the device ID and challenge on Pantahub does not claim the device.

**Diagnosis**: The device must be unclaimed and online when you claim it. The challenge token may also be stale.

**Fix**: Re-read the current values from the debug shell (`cat /pv/device-id`, `cat /pv/challenge`) and retry while the device is connected.

### `pvr post` / `pvr clone` fails with "connection refused"

**Symptom**: `pvr` cannot reach the device on the local network.

**Diagnosis**: Either the URL form is wrong, or the pvr-sdk endpoint on the device only binds localhost.

**Fix**: Use `http://<device-ip>:12368` (and `http://<device-ip>:12368/cgi-bin` for clone). If the image binds the endpoint to localhost, open it with a `_config/pvr-sdk/etc/pvr-sdk/config.json` overlay setting `"listen": "0.0.0.0"` — see the [FAQ entry](/meta-pantavisor/getting-started/troubleshooting/faq#pvr-clone-fails-with-connection-refused) for the exact JSON.

## Build & layer pitfalls (for image builders)

These apply when building Pantavisor images with Yocto or testing with `pv-appengine` — not to day-to-day device operation.

**`PANTAVISOR_FEATURES` operator**: never use `+=` in distro includes — it silently drops the defaults set by `pvbase.bbclass` (xconnect, pvcontrol, rngdaemon). Use `:append` instead; see the [FAQ entry](./faq/#why-are-xconnect-pvcontrol-or-rngdaemon-missing-from-my-image) for details.

**SRCREV bumps**: Always verify the commit hash against the actual remote — squash merges rewrite hashes. Update `PKGV` to match the latest tag reachable from the new SRCREV.

**Stale storage volume**: When testing with `pv-appengine`, pvtx.d scripts only run once per storage volume (when `.pvtx-done` is absent). Delete and recreate the volume between test runs:

```bash
docker volume rm storage-test
```

See the [FAQ](./faq/) for more specific questions and answers.
