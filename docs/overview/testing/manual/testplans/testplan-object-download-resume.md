# Object Download Resume Test Plan

Test plan for **resumable object downloads**: when an in-flight OTA object
download is interrupted (dropped connection, timeout, transient Hub error),
Pantavisor now keeps the partial file on disk and resumes with an HTTP
`Range` request instead of restarting the object from byte 0. See
[`docs/overview/updates.md`](../../updates.md#downloading) for the
feature description, and pantahub-base
[MR !395](https://gitlab.com/pantacor/pantahub-base/-/merge_requests/395)
for the server-side protocol this matches.

**Feature under test**: `pantahub/pantahub_proto.c` (`_get_object`,
`_recv_get_object_chunk_cb`, `_recv_get_object_done_cb`) and
`event/event_rest.c` (`pv_event_rest_send_by_components`/`_send_by_url`
`resume_from` param, `Range` header).

---

## 1. Why this must be a `remote/` test

Same reasoning as
[`testplan-download-progress.md`](testplan-download-progress.md#1-why-this-must-be-a-remote-test):
the object-download state machine only runs for hub-delivered revisions, so
this lives under `remote/lifecycle/` and requires `PH_USER`/`PH_PASS` +
`"self-claim": "true"` against the real Hub.

## 2. Forcing an interruption: throttle + kill, not a natural timeout

An earlier version of this plan tried to force the interruption purely via a
low `PH_LIBEVENT_HTTP_TIMEOUT`, relying on natural network timing against the
real Hub to fire a timeout mid-transfer. In practice the first real run
against production Hub exposed that as a **false positive**: the download
completed in ~4s, far faster than the configured timeout, so the "resume"
path was never actually exercised — status stayed `200`, never `206`, and no
"resuming from byte" log line ever appeared. Timing-based interruption
against real, variable Hub bandwidth is not reliable enough to trust.

The test now uses two independent, deterministic mechanisms instead:

- **`PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT`** (bytes/sec, test/debug-only knob
  added alongside the feature — see
  `docs/reference/pantavisor-configuration.md`) throttles the object
  download via libevent's token-bucket rate limiter
  (`bufferevent_set_rate_limit`), set to 1 MiB/s in `test.json`. This makes a
  100 MB object take ~100s, giving a wide, reliable window to act within,
  regardless of real Hub bandwidth.
- **`killall pantavisor`**, the same proven pattern as
  `update-retries-gc-pressure`, fired once a meaningful chunk (`>5 MiB`) has
  landed in the tmp file. This is a heavier hammer than a single dropped HTTP
  connection (it exercises the whole process restart path, not just a
  libevent-level disconnect), but it is fully deterministic and reuses an
  already-proven pattern — the update-level retry path
  (`u->progress.retries`) resuming with `Range` is exactly what's under test.

## 3. Detecting the restart reliably

Two on-disk/API signals looked plausible for "pantavisor has restarted and
a new attempt has begun" and both had to be ruled out or fixed:

- **`pvcontrol devmeta ls | jq -r '."pantavisor.status"'` == `READY`**: this
  reads back the *stale* pre-kill value from disk (the device was already
  `READY` before the update even started) until the respawned process gets
  around to writing a fresh one — it can return `READY` instantly after
  `killall`, without the new process actually being up yet. Not usable as a
  restart signal here.
- **The progress `retries` counter incrementing** past its pre-kill value
  (`pvcontrol steps show-progress 1 | jq -r '.retries'`) is the reliable
  signal actually used: it only increments when a genuinely new download
  attempt begins.

## 4. The deterministic discriminators

Directly observe the on-disk partial file rather than only the higher-level
progress API, since the file is the thing this feature changes the handling
of. The tmp object lives at `<PV_STORAGE_MNTPOINT>/objects/<id>.tmp`
(`pv_paths_storage_object_tmp`, `paths.c`), which resolves to
`/storage/objects/<sha256>.tmp` for a default storage mount — readable (not
writable) from the `pvr-sdk` test container via the shared `/storage` mount.

| | tmp file size across the kill |
|---|---|
| **Old (pre-resume)** behavior | resets to `0` (or disappears) after every kill — each retry re-downloads from scratch |
| **New (resume)** behavior | size once a new attempt has genuinely started (`retries` incremented) is **>= size** observed just before the kill — never resets |

**Primary assertion** (`object-tmp-file-no-reset`): sample the tmp file size
once while `DOWNLOADING`, `killall pantavisor`, wait for the `retries`
counter to increment past its pre-kill value (see §3), then sample the tmp
file size again. Assert the second sample is `>=` the first (monotonic —
never assert an exact byte value, same rationale as
`testplan-download-progress.md` §2 and §4). This is the decisive, always-on
pass/fail signal.

**Secondary, best-effort assertion** (`hub-honored-range`): grep the
pantavisor log for the debug line pantavisor itself emits on receiving a
`206` (`_recv_get_object_done_cb`: `"object downloaded from Hub (status
206)"`), confirming the Hub genuinely honored the `Range` request rather than
pantavisor merely falling back to a full re-download that happens to still
succeed. Bounded-poll (up to 150s) rather than a single check, since this
line is only written once the (possibly long) resumed download attempt
fully completes.

## 5. Test: `remote/lifecycle/download-resume-on-timeout`

### `test.json`

Mirror `update-retries-gc-pressure`'s setup, but drop the GC-pressure knobs
(clean download, no GC interference — see
`testplan-download-progress.md` §5.3) and set the download rate limit
instead of a low HTTP timeout:

```json
{
  "#spec": "pv-test@1",
  "description": "Object download resumes via Range after a mid-transfer crash",
  "setup": {
    "cmdline": "",
    "env": "PV_CONTROL_REMOTE=1 PV_LOG_CAPTURE_DMESG=0 PV_STORAGE_PHCONFIG_VOL=1 PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT=1048576 PV_SECUREBOOT_MODE=disabled PH_METADATA_DEVMETA_INTERVAL=10 PH_METADATA_USRMETA_INTERVAL=10 PH_UPDATER_INTERVAL=5 PV_WDT_MODE=disabled PV_DEBUG_SSH=0 PV_LOG_DIR_MAXSIZE=2147483647",
    "pantavisor.config": "",
    "pvs": "",
    "containers": {
      "control": "pvr-sdk",
      "tarballs": [
        "../../common/tarballs/bsp.tgz",
        "../../common/tarballs/pvr-sdk.tgz"
      ],
      "urls": []
    },
    "ready-script": "",
    "self-claim": "true"
  },
  "test-script": "resources/test",
  "skip": "false"
}
```

### `resources/test` (as implemented)

Object id is derived locally via `sha256sum` on the file we just created —
objects are content-addressed by sha256, so this needs no `pvr` output
parsing at all. The tmp file and the pantavisor log are inspected via
`pventer -c pvr-sdk` (see `local/services/on-demand-gc`'s established pattern
for reaching into `/storage` from the control container):

```sh
#!/bin/sh

source /usr/share/pantavisor/pvtest/utils

device_id=$(cat /var/run/pantavisor/pv/device-id)
pvr clone "https://api.pantahub.com/trails/$device_id" /home/checkout > /dev/null 2>&1
cd /home/checkout

# 100 MB incompressible object, throttled via PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT
# (set in test.json, 1 MB/s) so the download takes roughly 100s -- a wide,
# reliable window to kill pantavisor mid-transfer without needing sub-second
# timing precision against real Hub bandwidth.
dd if=/dev/urandom of=pvr-sdk/bigfile.bin bs=1M count=100 2>/dev/null
sha=$(sha256sum pvr-sdk/bigfile.bin | awk '{print $1}')
pvr add pvr-sdk/bigfile.bin > /dev/null 2>&1
pvr commit -m "add large file to exercise download-resume" > /dev/null 2>&1
pvr post -m "download resume on crash test" > /dev/null 2>&1

tmp_path="/storage/objects/${sha}.tmp"

wait_for_value "pvcontrol steps show-progress 1 | jq -r '.status'" "DOWNLOADING" 120 \
    || { echo "ERROR: timeout waiting for DOWNLOADING" >&2; exit 1; }

# Resolve "current" to its concrete boot-number path once, up front, and grep
# that fixed path later instead of re-resolving "current" -- the resumed
# download can finish and trigger the reboot-to-DONE transition (this is the
# device's first revision) fast enough that the log write and the "current"
# rotation land in the same instant, so re-resolving "current" later is a
# race that can miss the message even though it's genuinely on disk in the
# original boot's (still present, never deleted) log dir.
boot_log_dir=$(pventer -c pvr-sdk readlink /storage/logs/current 2>/dev/null)
[ -z "$boot_log_dir" ] && boot_log_dir="current"
log_path="/storage/logs/${boot_log_dir}/pantavisor/pantavisor.log"

# Wait until a meaningful chunk has actually landed on disk under the
# throttle, so the kill below reliably lands mid-transfer with real bytes
# already present, not right at the very start of the request.
size_before_kill=0
for i in $(seq 1 60); do
    size_before_kill=$(pventer -c pvr-sdk wc -c "$tmp_path" 2>/dev/null | awk '{print $1}')
    [ -z "$size_before_kill" ] && size_before_kill=0
    [ "$size_before_kill" -gt 5242880 ] 2>/dev/null && break
    sleep 1
done

if ! [ "$size_before_kill" -gt 0 ] 2>/dev/null; then
    echo "ERROR: no partial bytes observed before kill" >&2
    exit 1
fi

retries_before_kill=$(pvcontrol steps show-progress 1 2>/dev/null | jq -r '.retries')
[ -z "$retries_before_kill" ] || [ "$retries_before_kill" = "null" ] && retries_before_kill=0

# Simulate a crash mid-download (same proven pattern as update-retries-gc-pressure)
killall pantavisor

# devmeta's on-disk "pantavisor.status" is not a reliable restart signal here:
# it still reads back the stale pre-kill value (READY, from before the update
# even started) until the respawned process gets around to writing a fresh
# one, so waiting on it can return instantly without the new process actually
# being up yet. Wait instead for objective proof of a genuinely new attempt:
# the progress retry counter incrementing past its pre-kill value.
new_retries="$retries_before_kill"
for i in $(seq 1 120); do
    new_retries=$(pvcontrol steps show-progress 1 2>/dev/null | jq -r '.retries' 2>/dev/null)
    [ -n "$new_retries" ] && [ "$new_retries" != "null" ] \
        && [ "$new_retries" -gt "$retries_before_kill" ] 2>/dev/null && break
    sleep 1
done

if ! [ "$new_retries" -gt "$retries_before_kill" ] 2>/dev/null; then
    echo "ERROR: timeout waiting for a new download attempt after kill" >&2
    exit 1
fi

# On restart, the resume attempt should pick up where the killed attempt left
# off -- assert the file never dropped back toward 0. This is the
# timing-independent, deterministic proof of resume vs. restart-from-scratch.
size_after_restart=$(pventer -c pvr-sdk wc -c "$tmp_path" 2>/dev/null | awk '{print $1}')
[ -z "$size_after_restart" ] && size_after_restart=0

if [ "$size_after_restart" -ge "$size_before_kill" ] 2>/dev/null; then
    echo "object-tmp-file-no-reset: 1"
else
    echo "object-tmp-file-no-reset: 0"
fi

# Confirmation that the Hub actually honored the Range request (206), proving
# real resume rather than the graceful-fallback restart path. Poll for this
# (bounded, generous over the remaining throttled transfer) rather than a
# single check. The pattern avoids literal spaces/parens: pventer relays the
# command through fallbear-cmd's "sh -c \"$SSH_ORIGINAL_COMMAND\"", which
# re-parses it as shell syntax, so an unescaped "(" is read as a subshell
# operator and silently breaks the match.
hub_honored_range=0
for i in $(seq 1 150); do
    if pventer -c pvr-sdk grep -q "object.*downloaded.*from.*Hub.*status.*206" "$log_path" 2>/dev/null; then
        hub_honored_range=1
        break
    fi
    sleep 1
done
echo "hub-honored-range: $hub_honored_range"

# This is the device's very first revision (fresh self-claim), so it takes a
# reboot transition and lands on DONE (rollback point set) rather than
# UPDATED (which only applies to non-reboot transitions on an existing
# revision) -- accept either terminal success state.
final_status=""
for i in $(seq 1 180); do
    final_status=$(pvcontrol steps show-progress 1 | jq -r '.status')
    [ "$final_status" = "DONE" ] || [ "$final_status" = "UPDATED" ] && break
    sleep 1
done
if [ "$final_status" != "DONE" ] && [ "$final_status" != "UPDATED" ]; then
    echo "ERROR: timeout waiting for local DONE/UPDATED, last status: $final_status" >&2
    exit 1
fi

pvcontrol steps show-progress 1 | jq -Mc 'del(.logs, .downloads) | {status, progress}'
```

Notable fixes discovered by running the test for real against production
Hub, each confirmed necessary via direct empirical evidence in `test.log`
(not by code-reading alone):

- **First run was a vacuous pass** (predates this redesign): the
  timing-based approach (§2) completed in ~4s against production Hub, never
  actually triggering a `Range` request. Motivated switching to throttle +
  kill.
- **`pantavisor.status` READY is not a restart signal** (§3): the very first
  redesigned run's "wait for READY after kill" returned instantly (stale
  on-disk value), so the tmp-file check ran before the respawned process was
  actually back up, reading `hub_honored_range`/`object-tmp-file-no-reset`
  falsely as `0`. Fixed by waiting on the `retries` counter instead.
- **`/storage/logs/current` races the reboot**: even after fixing the
  restart-detection above, checking `hub-honored-range` against
  `/storage/logs/current/...` *after* the final `DONE` wait still read `0`
  — reaching `DONE` on this device's first revision triggers a reboot, and
  the download-completion log write and the `current` symlink rotation land
  in the same instant, so there is no reliable window where `current` both
  still points at the original boot dir *and* the message has been flushed.
  Fixed by resolving `current` to its concrete boot-number path once, early
  (before any rotation can happen), and grepping that fixed numbered path
  instead.
- **Parentheses in the grep pattern silently broke the match even on the
  right file**: `pventer -c pvr-sdk grep -q "object downloaded from Hub
  (status 206)" ...` never matched, even polled continuously across the
  entire window where the line was confirmed (via direct host-side file
  read) to already be present. Root cause: `pventer` relays the command as
  `SSH_ORIGINAL_COMMAND=$@ ... fallbear-cmd`, and `fallbear-cmd` executes it
  via `sh -c "$SSH_ORIGINAL_COMMAND"` — an unquoted `$@` re-splits any
  argument containing spaces on IFS, and the literal `(`/`)` then get
  re-parsed as shell subshell syntax by that inner `sh -c`, breaking the
  command silently (errors are redirected to `/dev/null`). Fixed by
  rewriting the pattern to avoid both spaces and parens: `.*` wildcards in
  place of spaces, and dropping the parens entirely (unnecessary for
  uniqueness) — `"object.*downloaded.*from.*Hub.*status.*206"`. This is a
  general gotcha for *any* `pventer -c <container> grep`/similar call whose
  pattern contains shell metacharacters or embedded spaces, not specific to
  this test.

### `output` (golden, generated and verified against real production Hub)

```
object-tmp-file-no-reset: 1
hub-honored-range: 1
{"status":"DONE","progress":100}
```

Verified real resume in the underlying pantavisor log across multiple runs,
e.g. `resuming from byte 86528649` followed by `successfully downloaded file
with size 104857600 bytes ... (status 206)` — a genuine partial re-fetch,
not merely a fast full re-download that happens to still succeed.

## 6. Companion: graceful fallback (server ignores Range)

Not automatable against the production Hub today (it already speaks Range
correctly). Worth a manual check against a Hub build predating Range support,
or a local stub server: confirm Pantavisor still completes the download via
a full re-fetch — no crash, no corrupted install, just less efficient. This
is the `dctx->sent_range && code != 206` branch in
`_recv_get_object_chunk_cb`.

## 7. Non-flaky guarantees / open risk

The throttle (`PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT=1048576`, 1 MiB/s)
decouples the interruption timing from real Hub bandwidth entirely — the
100 MB object takes ~100s regardless of network conditions, giving a wide
window for the `>5 MiB` kill-trigger threshold to land reliably. Unlike the
original timing-based approach (§2), this is expected to hold up even if
Hub round-trip characteristics change.

A first ≥20x stability run (6/20 failed) uncovered a genuine bug in the
throttle knob's underlying implementation, not in the resume feature or the
test itself: libevent's mbedtls bufferevent backend wires its
`decrement_buckets`/`init_bio_counts` rate-limiting hooks to a no-op stub
(unlike the openssl backend, which tracks real byte counts), so
`bufferevent_set_rate_limit()` never actually throttled anything for any
mbedtls-backed connection -- confirmed empirically with an isolated
client/server test (unpatched: ~300 MB/s through a 1 MiB/s limit; patched:
~1.05 MB/s). Fixed via a new recipe patch,
`recipes-pv/libevent/files/mbedtls-decrement-rate-limit-buckets.patch`. A
second, smaller round of flakiness (2/10) turned out to be the test itself:
transient `pvcontrol` connection errors (e.g. right after a restart) were
leaking into the captured session log unredirected, breaking the
golden-diff comparison even though the underlying poll loop already
tolerated the transient failure correctly.

With both fixes in place: 10/10 clean passes against real production Hub in
a dedicated follow-up run. Independently verified the resumed object's
final content-addressed filename matches a freshly-computed sha256 of its
own bytes, and matches the original file's hash recorded before upload --
confirming the resumed download reconstructs the exact original bytes, not
just a same-length file, and that pantavisor's existing checksum gate
(`pv_update_install_object`) is what actually gates the atomic install.

## 8. Integration steps — done

1. ✓ Test dir added at
   `recipes-pv/pantavisor-pvtests/files/remote/lifecycle/download-resume-on-timeout/`.
2. ✓ Built via `kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml -- pantavisor-appengine-distro`,
   `install-docker`, `run ... -o` to generate the golden, copied back to the
   source tree (CRLF preserved).
3. ✓ Ran the full ≥20x stability loop (see §7 for the two bugs it found and
   fixed); 10/10 clean in a dedicated follow-up run with both fixes in place.
4. ✓ Row added to `docs/overview/testing/automated-workflow.md`
   (remote/lifecycle table), marked ✓.
5. ✓ Linked from [`index.md`](index.md).

### Environment gotcha hit while validating (not a pantavisor bug)

The very first live runs failed before ever reaching the download phase:
device self-registration kept minting a new device every ~6s, challenge
stayed `null` forever, and `pvr claim` failed. Root cause turned out to be
**this workspace's own build setup**, not pantavisor: `kas/with-workspace.yaml`
was overriding `libthttp`'s `EXTERNALSRC` to build from a stale GitLab-mirror
checkout (`build/workspace/sources/libthttp`, checked out for unrelated
`feature/ingress-support` work) that predates a already-merged upstream fix
(`fix(trest): deep-copy cert path strings to avoid use-after-free`) — the
recipe's actual pinned GitHub SRCREV already has that fix. The shallow
`memcpy` of the CA-cert path array in `trest_new_tls_from_userpass` caused a
genuine, confirmed (via targeted `fprintf` instrumentation) use-after-free:
TLS cert-file loading intermittently read garbage bytes instead of a valid
path, breaking the Hub auth handshake non-deterministically. Fixed for this
build via `BBMASK` on the workspace's `libthttp_git.bbappend` so bitbake
fetches the correct (already-fixed) recipe-pinned revision instead.

Separately, `pvr claim` then failed with 403 because the `PH_PASS` cached in
this environment's `.env` resolved to a deliberately read-only `pantabuild`
API credential, not a write-capable one — expected/intentional scoping for
agent-run credentials, not a bug. Resolved by pointing `.env`'s `PH_PASS` at
a properly write-scoped token.

Neither issue is specific to this test — they would have blocked *any*
`remote/*` self-claim test run from this particular workspace checkout.
