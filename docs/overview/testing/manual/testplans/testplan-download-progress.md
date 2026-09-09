# Download-Progress Reporting Test Plan

While an object is being downloaded, the progress of the revision advances
continuously, on the device and on the Hub. Before pantavisor #750 it only
moved when a whole object had been downloaded.

**Scope**: a device claimed on Pantacor Hub downloading one large object.

---

## Automated Coverage

`remote/lifecycle/download-progress-continuous` runs Tests 1 to 3 below against
an appengine and prints one marker per check:

| Test | Markers in `output` |
|------|---------------------|
| 1 | `local-intermediate-progress-observed: 1`, `local-monotonic-non-decreasing: 1`, `local-no-overshoot: 1` |
| 2 | `cloud-intermediate-progress-observed: 1`, `cloud-monotonic-non-decreasing: 1`, `cloud-no-overshoot: 1` |
| 3 | `{"status":"UPDATED","progress":100}`, `cloud-final-status: UPDATED` |

The test samples the device every second and the Hub every five seconds and
never asserts a byte value or a sample count, only the three properties.

---

## Prerequisites

- A device claimed on the Hub, with shell access and `pvcontrol` on it.
- `pvr` on the workstation, logged in to the same Hub.

Throttle the download so the object takes about a minute. On the device:

```bash
pvcontrol usrmeta save PH_UPDATER_DOWNLOAD_RATE_LIMIT 1048576
```

Post a revision that adds exactly one 50 MB object. On the workstation:

```bash
pvr clone https://pvr.pantahub.com/<user>/<nick> big && cd big
dd if=/dev/urandom of=<app>/bigfile.bin bs=1M count=50
pvr add <app>/bigfile.bin && pvr commit -m "big object" && pvr post -m "progress test"
pvr device status <nick>           # note the revision number
```

Teardown, on the device:

```bash
pvcontrol usrmeta delete PH_UPDATER_DOWNLOAD_RATE_LIMIT
```

---

## Test 1: Progress on the device

### Execute

On the device, while the status is `DOWNLOADING`:

```bash
watch -n1 "pvcontrol steps show-progress <rev> | jq '.downloads.total | {total_downloaded, total_size}'"
```

### Expected

- `total_downloaded` climbs through values between `0` and `total_size` in
  steps of a few MB, every 6 seconds. Old code showed `0` and then jumped to
  `total_size`.
- It never decreases and never exceeds `total_size`.

---

## Test 2: Progress on the Hub

### Execute

On the workstation, during the same download:

```bash
watch -n5 "pvr stepinfo https://api.pantahub.com/trails/<device-id>/steps/<rev> | sed -n '/^{/,\$p' | jq '.progress.downloads.total | {total_downloaded, total_size}'"
```

### Expected

- Same as Test 1, with fewer distinct values and a few seconds behind the
  device. The Hub reports are coalesced, so not every heartbeat shows up.

---

## Test 3: Completion

### Execute

After the download:

```bash
pvcontrol steps show-progress <rev> | jq '{status, progress}'
pvr stepinfo https://api.pantahub.com/trails/<device-id>/steps/<rev> | sed -n '/^{/,$p' | jq '.progress.status'
```

### Expected

- `{"status": "UPDATED", "progress": 100}` on the device.
- `"UPDATED"` on the Hub.
