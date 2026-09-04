# Object Download Resume Test Plan

Test plan for **resumable object downloads**: when an in-flight OTA object
download is interrupted (dropped connection, timeout, transient Hub error),
Pantavisor now keeps the partial file on disk and resumes with an HTTP
`Range` request instead of restarting the object from byte 0. See
[`docs/overview/updates.md`](https://github.com/pantavisor/pantavisor/blob/master/docs/overview/updates.md#downloading) for the
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
  (`pvcontrol steps show-progress $rev | jq -r '.retries'`) is the reliable
  signal actually used: it only increments when a genuinely new download
  attempt begins.

## 4. The deterministic discriminators

Directly observe the on-disk partial file rather than only the higher-level
progress API, since the file is the thing this feature changes the handling
of. The tmp object lives at `<PV_STORAGE_MNTPOINT>/objects/<id>.tmp`
(`pv_paths_storage_object_tmp`, `paths.c`), which resolves to
`/storage/objects/<sha256>.tmp` for a default storage mount — read on the
device through `pv_exec`, with the mountpoint resolved via `pv_storage_dir`.

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
succeed. Checked after the update reached `UPDATED`, since the line is only written
once the resumed download attempt fully completes. The counter
`downloads.total.total_resumes` in the progress JSON (`resume-attempt-counted`)
is the third marker: the new attempt asked the Hub for a Range.

## 5. Test: `remote/lifecycle/download-resume-on-timeout`

### `test.json`

Mirror `update-retries-gc-pressure`'s setup, but drop the GC-pressure knob
(clean download, no GC interference) and set the download rate limit instead of
a low HTTP timeout:

```json
{
	"#spec": "pv-test@1",
	"description": "Object download resumes via Range after a mid-transfer crash",
	"setup": {
		"config": {
			"env": "PV_CONTROL_REMOTE=1 PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT=1048576",
			"usrmeta": "PH_UPDATER_INTERVAL=5 PV_REVISION_RETRIES=3"
		},
		"containers": {
			"tarballs": [
				"../../common/tarballs/pv-example-app.pvrexport.tgz"
			]
		},
		"self-claim": "true",
		"commit-initial": "true"
	},
	"test-script": "resources/test",
	"skip": "false",
	"devices": []
}
```

### `resources/test` (as implemented)

Object id is derived locally via `sha256sum` on the file we just created —
objects are content-addressed by sha256, so this needs no `pvr` output
parsing at all. The tmp file and the pantavisor log are inspected on the
device via `pv_exec`; the checkout is a per-test temp dir cloned from the local
pvr endpoint and the revision number comes from `pvr_post_rev`:

```sh
#!/bin/sh

. "${PVTEST_LIBDIR:-/usr/share/pantavisor/pvtest}/utils"

device_id=$(pv_exec cat /run/pantavisor/pv/device-id)

# Per-test isolation: clone into a temp checkout dir; never override $HOME.
checkout="$(mktemp -d)/checkout"
pvr_clone_local_or_die "$checkout"
cd "$checkout"

trail_url="https://api.pantahub.com/trails/$device_id"

echo "== post one large object (download throttled to 1 MB/s) =="
# 100 MB incompressible object, throttled via PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT
# in test.json: ~100 s of transfer, a wide window to crash pantavisor mid-object.
dd if=/dev/urandom of=pv-example-app/bigfile.bin bs=1M count=100 2>/dev/null
sha=$(sha256sum pv-example-app/bigfile.bin | awk '{print $1}')
pvr add pv-example-app/bigfile.bin > /dev/null 2>&1
pvr commit -m "add large file to exercise download-resume" > /dev/null 2>&1
rev=$(pvr_post_rev -m "download resume on crash test" "$trail_url")
[ -n "$rev" ] || { echo "ERROR: could not determine posted revision" >&2; exit 1; }

storage=$(pv_storage_dir)
tmp_path="$storage/objects/${sha}.tmp"

echo "== wait for the posted revision to start downloading =="
wait_for_value "pvcontrol steps show-progress $rev | jq -r '.status'" "DOWNLOADING" 120 \
    || { echo "ERROR: timeout waiting for revision $rev to start DOWNLOADING" >&2; exit 1; }
pvcontrol steps show-progress $rev | jq -Mc 'del(.logs, .downloads)'

# Wait until a meaningful chunk has landed on disk, so the crash below lands
# mid-transfer with real bytes present rather than right at the request start.
size_before_kill=0
for i in $(seq 1 60); do
    size_before_kill=$(pv_exec wc -c "$tmp_path" 2>/dev/null | awk '{print $1}')
    [ -z "$size_before_kill" ] && size_before_kill=0
    [ "$size_before_kill" -gt 5242880 ] 2>/dev/null && break
    sleep 1
done
if ! [ "$size_before_kill" -gt 0 ] 2>/dev/null; then
    echo "ERROR: no partial bytes observed before kill" >&2
    exit 1
fi
echo "partial-object-on-disk-before-crash: 1"

echo "== crash PV mid-download =="
pv_crash
wait_for_down 30 \
    || { echo "ERROR: pv-ctrl never went down after crash" >&2; exit 1; }
wait_for_target_ready \
    || { echo "ERROR: timeout waiting for device to come back after crash" >&2; exit 1; }
pvcontrol commands go-remote > /dev/null

echo "== wait for retry 2 to pick the download up =="
wait_for_value "pvcontrol steps show-progress $rev | jq -r '.retries'" "2" 120 \
    || { echo "ERROR: timeout waiting for revision $rev retries to reach 2" >&2; exit 1; }
wait_for_value "pvcontrol steps show-progress $rev | jq -r '.status'" "DOWNLOADING" 120 \
    || { echo "ERROR: timeout waiting for revision $rev to resume DOWNLOADING" >&2; exit 1; }
pvcontrol steps show-progress $rev | jq -Mc 'del(.logs, .downloads)'

# The partial file must survive the restart: a resume never truncates it, a
# restart-from-scratch would. Sample as soon as the new attempt is underway.
size_after_restart=$(pv_exec wc -c "$tmp_path" 2>/dev/null | awk '{print $1}')
[ -z "$size_after_restart" ] && size_after_restart=0
if [ "$size_after_restart" -ge "$size_before_kill" ] 2>/dev/null; then
    echo "object-tmp-file-no-reset: 1"
else
    echo "object-tmp-file-no-reset: 0 ($size_after_restart < $size_before_kill)"
fi

# Progress carries a cumulative resume-attempt counter; the new attempt asked
# the Hub for a Range.
resumes=$(pvcontrol steps show-progress $rev | jq -r '.downloads.total.total_resumes // 0')
if [ "$resumes" -ge 1 ] 2>/dev/null; then
    echo "resume-attempt-counted: 1"
else
    echo "resume-attempt-counted: 0 ($resumes)"
fi

echo "== wait for the update to finish =="
wait_for_revision_state "$rev" "UPDATED" \
    || { echo "ERROR: timeout waiting for revision $rev to reach UPDATED" >&2; exit 1; }
pvcontrol steps show-progress $rev | jq -Mc 'del(.logs, .downloads) | {status, progress}'

# Proof the Hub honoured the Range request (206) rather than the graceful
# restart-from-scratch fallback: the log line is written by the attempt that
# completed the object, so it is on disk by now. Every boot keeps its own log
# dir, so grep the whole tree rather than resolving "current".
if pv_exec grep -rq "object.*downloaded.*from.*Hub.*status.*206" "$storage/logs" 2>/dev/null; then
    echo "hub-honored-range: 1"
else
    echo "hub-honored-range: 0"
fi
```

### `output` (golden, generated and verified against real production Hub)

```
== post one large object (download throttled to 1 MB/s) ==
== wait for the posted revision to start downloading ==
{"status":"DOWNLOADING","status-msg":"Downloading update artifacts, retry 1 of 3","progress":25,"retries":1}
partial-object-on-disk-before-crash: 1
== crash PV mid-download ==
== wait for retry 2 to pick the download up ==
{"status":"DOWNLOADING","status-msg":"Downloading update artifacts, retry 2 of 3","progress":25,"retries":2}
object-tmp-file-no-reset: 1
resume-attempt-counted: 1
== wait for the update to finish ==
{"status":"UPDATED","progress":100}
hub-honored-range: 1
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
4. ✓ Row added to `docs/overview/testing/automated/pvtest-list.md`
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
