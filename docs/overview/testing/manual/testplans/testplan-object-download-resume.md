# Object Download Resume Test Plan

Pantavisor keeps a partially downloaded object across an interruption and
continues it with an HTTP `Range` request instead of downloading the object
again from byte 0 (pantavisor #770, Hub side pantahub-base !395).

**Scope**: a device claimed on Pantacor Hub, interrupted in the middle of an
object download by a reboot.

---

## Automated Coverage

`remote/lifecycle/download-resume-on-timeout` runs Tests 1 to 4 below against
an appengine, interrupting with `pv_crash` instead of a reboot. Its markers:

| Test | Marker in `output` |
|------|--------------------|
| 1 | `partial-object-on-disk-before-crash: 1` |
| 2 | `object-tmp-file-no-reset: 1` |
| 3 | `resume-attempt-counted: 1` |
| 4 | `hub-honored-range: 1` |

Not automated: Test 5, a Hub that does not support `Range`.

---

## Prerequisites

- A device claimed on the Hub, with shell access and `pvcontrol` on it.
- `pvr` on the workstation, logged in to the same Hub.

Throttle the download so there is time to interrupt it. On the device:

```bash
pvcontrol usrmeta save PH_UPDATER_DOWNLOAD_RATE_LIMIT 1048576
```

Post a revision with one 100 MB object. On the workstation:

```bash
pvr clone https://pvr.pantahub.com/<user>/<nick> big && cd big
dd if=/dev/urandom of=<app>/bigfile.bin bs=1M count=100
sha256sum <app>/bigfile.bin        # note the hash, the partial file is named after it
pvr add <app>/bigfile.bin && pvr commit -m "big object" && pvr post -m "resume test"
pvr device status <nick>           # note the revision number
```

Teardown, on the device:

```bash
pvcontrol usrmeta delete PH_UPDATER_DOWNLOAD_RATE_LIMIT
```

---

## Test 1: Partial object on disk

### Execute

On the device, once `pvcontrol steps show-progress <rev>` shows `DOWNLOADING`:

```bash
ls -l /storage/objects/<sha>.tmp
```

### Expected

- The file exists and grows by about 1 MB per second.

---

## Test 2: Partial object survives the interruption

### Execute

Wait until the file is larger than 5 MB and note its size. Then reboot the
device hard (power cycle, or `reboot -f`). After it is back:

```bash
pvcontrol steps show-progress <rev> | jq '{status, retries}'
ls -l /storage/objects/<sha>.tmp
```

### Expected

- `status` is `DOWNLOADING` and `retries` is `2`.
- The file is at least as large as before the reboot. It was not truncated.

---

## Test 3: Resume counter

### Execute

Within about 10 seconds of Test 2:

```bash
pvcontrol steps show-progress <rev> | jq '.downloads.total.total_resumes'
```

### Expected

- `1`. The counter is written with the next download heartbeat, so it can
  read `0` for a few seconds after the restart.

---

## Test 4: Hub answered the Range request

### Execute

Wait for the update to finish, then:

```bash
pvcontrol steps show-progress <rev> | jq '{status, progress}'
grep -rh "resuming from byte\|status 206" /storage/logs/*/pantavisor/pantavisor.log
```

### Expected

- `{"status": "UPDATED", "progress": 100}`.
- One line `requesting object '<sha>' from Hub, resuming from byte <n>` and one
  line ending in `(status 206)`. A `200` there means the Hub ignored the range
  and the object was downloaded again from the start.

---

## Test 5: Hub without Range support (manual only)

Needs a Hub build without pantahub-base !395, or a stub object server that
answers `200` to a ranged request.

### Execute

Repeat Tests 1 and 2.

### Expected

- The update still reaches `UPDATED`.
- The log shows the object downloaded with status `200`, and the partial file
  was replaced, not appended to.
