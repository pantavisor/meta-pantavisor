# Download-Progress Reporting Test Plan

Test plan for the OTA **download-progress** reporting introduced in
pantavisor PR #750 (`fix(update): report download progress on the mainloop
heartbeat, not per object`).

**Scope**: validate that during an OTA object download, the per-revision
progress artifact (`.pv/progress`, surfaced by `pvcontrol steps show-progress
<rev>`) advances **continuously while a single object is still downloading** —
rather than only jumping at whole-object completion.

**Feature under test**: `update/update_progress.c`, `update/update.c`,
`pantahub/pantahub_proto.c`, `pantahub/pantahub.c` — per-chunk in-memory
accounting (`pv_update_add_downloaded`) reported on the 6 s download heartbeat
(`pv_update_report_download_progress` from `_download_objects_cb`).

---

## 1. Why this must be a `remote/` test

The object-download state machine (`_run_state_download` →
`_download_objects_cb` → `pv_pantahub_proto_get_objects`) runs **only for
hub-delivered revisions**. A local `pvr post` against
`http://localhost:12368/cgi-bin/pvr` (as in `local/lifecycle/seq-non-reboot-updates`)
installs objects directly and never enters the pantahub download path, so it
cannot exercise progress reporting.

The test therefore lives under `remote/lifecycle/` and, like the other remote
tests, requires `PH_USER`/`PH_PASS` in env and `"self-claim": "true"`, hitting
the production hub at `https://api.pantahub.com`. Model it on
[`remote/lifecycle/update-retries-gc-pressure`](../../../../../recipes-pv/pantavisor-pvtests/files/remote/lifecycle/update-retries-gc-pressure)
— the closest existing test — which proves a `dd`-generated large object gives a
reliably observable `DOWNLOADING` window in the harness environment.

### Two observation surfaces — both asserted, different purposes

The same serializer (`_report` → `report_cb` / `pv_storage_set_rev_progress`)
feeds **two independent sinks**, and we assert on both:

1. **Local file** — `/var/pantavisor/storage/trails/<rev>/.pv/progress`, written
   on-device. `pvcontrol steps show-progress <rev>` just opens and streams it
   back (`ctrl/ctrl_steps_ep.c` `ctrl_steps_progress` — no live computation, no
   network). This is the **reliable backbone**: it's written on every 6 s
   heartbeat regardless of whether the Hub `PUT /steps/<rev>/progress` succeeds,
   queues, or drops, so a flaky reporting-*back* path cannot perturb it. It
   proves the **device computes** continuous progress.

2. **Cloud step** — `pvr stepinfo https://api.pantahub.com/trails/<id>/steps/<rev>`,
   under `.progress.*`. This proves the full **end-to-end** path
   (device → coalesced `PUT` → hub ingest → what the WebUI bar reads). This is
   the surface the original bug was reported against, so it must be covered.

Purpose split: the local assertion isolates "does PV report continuously?"; the
cloud assertion isolates "does that reach the hub?". Keeping them as **separate
marker lines in the same test** means a cloud-only flake (ingest lag,
coalescing) points precisely at the PUT path without masking the reliable local
result. The hub is needed only to *serve object bytes* and to *ingest the PUTs*;
neither requires guessing timing if we assert inequalities, not values.

> **Cloud caveat (why it's the softer of the two):** the hub push is coalesced —
> at most one in-flight PUT plus one queued (`pv_pantahub_proto_queue_progress`),
> draining on the PUT response. If the hub is slow, intermediate heartbeats
> collapse, so fewer distinct values reach the cloud than the local file. For a
> multi-heartbeat download this still yields ≥1 mid-flight cloud value, but it is
> more timing-sensitive than local — see §5 for the shared mitigation and the
> split-out fallback.

---

## 2. The flakiness problem, and the deterministic discriminator

The whole point of the fix — *intermediate* byte progress — is driven by a
**wall-clock heartbeat** (`REQ_INTERVAL = 6 s`, a compile-time constant in
`pantahub/pantahub.c`, **not** env-tunable) crossed with real download speed.
So the **byte values and the number of progress updates are inherently
timing-dependent**. A test that asserts "we saw N updates" or any specific
`total_downloaded` value **will flake**. Never assert on those.

The signal that separates fixed-vs-broken behavior **without** depending on how
many updates land is a single strict inequality observed while `status ==
DOWNLOADING`, for a revision that changes **exactly one large object**:

| | `total_downloaded` seen during `DOWNLOADING` (single object) |
|---|---|
| **Old (broken)** code | `0` for the entire download, then it jumps straight to `total_size` at object completion — **never strictly between**. |
| **New (fixed)** code | climbs through `0 < total_downloaded < total_size` at every heartbeat that lands mid-object. |

**Assertion**: over the download window, observe at least one snapshot with
`0 < total_downloaded < total_size` (strictly). The strictness matters — the
old code briefly writes `total_downloaded == total_size` while still nominally
`DOWNLOADING` (the FSM transition happens on the next tick), so a non-strict
`total_downloaded > 0` check would *not* separate old from new. `0 < x < size`
does: the old code produces only `{0}` and `{size}`, never a value in between.

This is robust **by construction** as long as the single object's download spans
more than one heartbeat (so ≥1 heartbeat lands with partial bytes). See §5 for
how we guarantee that.

---

## 3. Test: `remote/lifecycle/download-progress-continuous`

### `test.json`

Mirror `update-retries-gc-pressure`, but **without** the GC-pressure knobs
(`PV_STORAGE_GC_THRESHOLD=100`, low retries) — we want a clean, uninterrupted
download. The object download is throttled to 1 MiB/s with
`PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT` (the test/debug knob that shipped with
the download-resume feature, see
[testplan-object-download-resume.md](testplan-object-download-resume.md#2-forcing-an-interruption-throttle--kill-not-a-natural-timeout)),
so a 50 MB object spans ~50 s and many 6 s heartbeats whatever the real Hub
bandwidth is.

```json
{
	"#spec": "pv-test@1",
	"description": "Download progress reported continuously mid-object",
	"setup": {
		"config": {
			"env": "PV_CONTROL_REMOTE=1 PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT=1048576",
			"usrmeta": "PH_UPDATER_INTERVAL=5"
		},
		"containers": {
			"tarballs": [
				"../../common/tarballs/pv-example-app.pvrexport.tgz"
			]
		},
		"self-claim": "true"
	},
	"test-script": "resources/test",
	"skip": "false",
	"devices": []
}
```

### `resources/test`

Everything volatile is consumed inside the script; only fixed marker strings are
`echo`ed (the golden-diff surface). All assertions are timing-independent
booleans or state-machine enums. The checkout is a per-test temp dir cloned
from the local pvr endpoint, and the revision is posted to the Hub with
`pvr_post_rev` so the volatile revision number never reaches stdout.

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
# Exactly ONE new object: a single object is what separates "progress moves
# mid-object" from "progress jumps at object boundaries". 50 MB at the 1 MB/s
# throttle from test.json spans many 6 s download heartbeats.
dd if=/dev/urandom of=pv-example-app/bigfile.bin bs=1M count=50 2>/dev/null
pvr add pv-example-app/bigfile.bin > /dev/null 2>&1
pvr commit -m "add single large object to exercise download progress" > /dev/null 2>&1
rev=$(pvr_post_rev -m "download progress continuous test" "$trail_url")
[ -n "$rev" ] || { echo "ERROR: could not determine posted revision" >&2; exit 1; }
cloud_step_url="$trail_url/steps/$rev"

echo "== wait for the posted revision to start downloading =="
wait_for_value "pvcontrol steps show-progress $rev | jq -r '.status'" "DOWNLOADING" 120 \
    || { echo "ERROR: timeout waiting for revision $rev to start DOWNLOADING" >&2; exit 1; }

echo "== sample progress through the download window =="
# Local: the per-revision progress via pvcontrol, every second.
# Cloud: pvr stepinfo, every ~5 s to spare the Hub.
# Only timing-independent properties are asserted; accumulate booleans.
loc_intermediate=0; loc_monotonic=1; loc_no_overshoot=1; loc_prev=0
cld_intermediate=0; cld_monotonic=1; cld_no_overshoot=1; cld_prev=0
for i in $(seq 1 240); do
    snap=$(pvcontrol steps show-progress $rev 2>/dev/null)
    st=$(echo "$snap" | jq -r '.status' 2>/dev/null)
    if [ "$st" != "DOWNLOADING" ]; then
        [ "$st" = "NEW" ] || [ "$st" = "QUEUED" ] || break
        sleep 1; continue
    fi

    dl=$(echo "$snap" | jq -r '.downloads.total.total_downloaded // 0')
    sz=$(echo "$snap" | jq -r '.downloads.total.total_size // 0')
    [ "$dl" -ge "$loc_prev" ] 2>/dev/null || loc_monotonic=0
    if [ "$sz" -gt 0 ] 2>/dev/null; then
        [ "$dl" -le "$sz" ] 2>/dev/null || loc_no_overshoot=0
        [ "$dl" -gt 0 ] 2>/dev/null && [ "$dl" -lt "$sz" ] 2>/dev/null && loc_intermediate=1
    fi
    loc_prev="$dl"

    if [ $((i % 5)) -eq 0 ]; then
        csnap=$(pvr stepinfo "$cloud_step_url" 2>/dev/null | sed -n '/^{/,$p')
        cst=$(echo "$csnap" | jq -r '.progress.status // empty' 2>/dev/null)
        if [ "$cst" = "DOWNLOADING" ]; then
            cdl=$(echo "$csnap" | jq -r '.progress.downloads.total.total_downloaded // 0')
            csz=$(echo "$csnap" | jq -r '.progress.downloads.total.total_size // 0')
            [ "$cdl" -ge "$cld_prev" ] 2>/dev/null || cld_monotonic=0
            if [ "$csz" -gt 0 ] 2>/dev/null; then
                [ "$cdl" -le "$csz" ] 2>/dev/null || cld_no_overshoot=0
                [ "$cdl" -gt 0 ] 2>/dev/null && [ "$cdl" -lt "$csz" ] 2>/dev/null && cld_intermediate=1
            fi
            cld_prev="$cdl"
        fi
    fi
    sleep 1
done

echo "local-intermediate-progress-observed: $loc_intermediate"
echo "local-monotonic-non-decreasing: $loc_monotonic"
echo "local-no-overshoot: $loc_no_overshoot"
echo "cloud-intermediate-progress-observed: $cld_intermediate"
echo "cloud-monotonic-non-decreasing: $cld_monotonic"
echo "cloud-no-overshoot: $cld_no_overshoot"

echo "== wait for the update to finish locally and on the Hub =="
wait_for_revision_state "$rev" "UPDATED" \
    || { echo "ERROR: timeout waiting for revision $rev to reach UPDATED" >&2; exit 1; }
pvcontrol steps show-progress $rev | jq -Mc 'del(.logs, .downloads) | {status, progress}'

wait_for_value "pvr stepinfo $cloud_step_url 2>/dev/null | sed -n '/^{/,\$p' | jq -r '.progress.status // empty'" "UPDATED" 120 \
    || { echo "ERROR: timeout waiting for cloud UPDATED" >&2; exit 1; }
echo "cloud-final-status: UPDATED"
```

### `output` (golden)

Generated with `run … -o`; the diffed stdout is:

```
== post one large object (download throttled to 1 MB/s) ==
== wait for the posted revision to start downloading ==
== sample progress through the download window ==
local-intermediate-progress-observed: 1
local-monotonic-non-decreasing: 1
local-no-overshoot: 1
cloud-intermediate-progress-observed: 1
cloud-monotonic-non-decreasing: 1
cloud-no-overshoot: 1
== wait for the update to finish locally and on the Hub ==
{"status":"UPDATED","progress":100}
cloud-final-status: UPDATED
```

We deliberately **omit `retries`** from the final local assertion — a transient
hub hiccup could bump it to 1 without indicating a real failure. `status` and
the fixed step-mapped `progress` int (100 for UPDATED) are deterministic on both
surfaces.

---

## 4. What we assert vs. what we never assert

Applies to **both** the local (`pvcontrol steps show-progress`) and cloud
(`pvr stepinfo … .progress`) surfaces:

| Assert (deterministic) | Never assert (volatile / timing-dependent) |
|---|---|
| `0 < total_downloaded < total_size` observed **at least once** (per surface) | any specific `total_downloaded` value |
| `total_downloaded` monotonic non-decreasing | number of progress updates / heartbeats seen (esp. cloud — coalescing collapses them) |
| `total_downloaded <= total_size` always (rollback correctness) | `start_time`, `current_time`, elapsed time |
| terminal `status == UPDATED` (local **and** cloud), local `progress == 100` | `status-msg` during DOWNLOADING (`"Download progress N/M"`) |
| — | that the local and cloud byte values **agree** at any instant (cloud lags the local file) |
| — | that `total_downloaded` reaches exactly `total_size` (the FSM may leave DOWNLOADING before the final heartbeat writes the full value) |

---

## 5. Non-flaky guarantees (read before implementing)

The `intermediate-progress-observed: 1` assertion is robust **only if the single
object's download outlasts more than one 6 s heartbeat**. Controls:

1. **Throttle, not object sizing.** `PH_LIBEVENT_HTTP_DOWNLOAD_RATE_LIMIT=1048576`
   pins the transfer to ~1 MiB/s, so the 50 MB object takes ~50 s regardless of
   Hub bandwidth: ≈8 mid-download heartbeats, guaranteed. The throttle only
   works with the libevent mbedtls rate-limit fix shipped in
   `recipes-pv/libevent/files/mbedtls-decrement-rate-limit-buckets.patch`
   (without it the download runs at line speed and this assertion can
   false-negative).
2. **Single object only.** Add exactly one new file so the download is one
   object; this is what makes "0 vs strictly-between" a clean old/new separator
   (multiple objects would show inter-object intermediate values even on old
   code, muddying the signal).
3. **No GC interference.** Do **not** set the GC-pressure knobs, so a large
   in-flight download is not deleted mid-transfer (which would inject retries).
4. **Generous, bounded waits.** `wait_for_value ... 120/180` absorbs normal hub
   latency without turning byte-timing into a pass/fail axis.
5. **Golden hygiene.** Only fixed marker strings and `jq`-stripped enums reach
   stdout; nothing volatile (revision numbers, byte counts, timestamps) is printed.

**Cloud-surface fallback.** The cloud marker is the softer one (coalescing +
ingest lag). If `local-*` is solid but `cloud-intermediate` is occasionally `0`,
do **not** weaken the local assertions: lower the rate limit (longer window, more
PUTs land mid-flight) or, as a last resort, reduce the cloud assertion to
end-to-end reachability only (`cloud-final-status: UPDATED`).

---

## 6. Optional companion: rollback / no-overshoot on retry

The per-transfer rollback (`pv_update_add_downloaded(-received)` in
`_recv_get_object_done_cb`) guards against `total_downloaded` exceeding
`total_size` when an object fails partway and re-downloads. The `no-overshoot`
invariant above already covers the happy path. To exercise the *retry* path
deterministically, extend the script `update-retries-gc-pressure`-style
(`killall pantavisor` mid-download, wait for READY + re-`DOWNLOADING`), keeping
the same `no-overshoot` sampler across the retry. Note a PV **crash** restarts
from `downloaded = 0` (fresh process), so this exercises the bounded-accumulator
invariant, not the in-process `-received` rollback specifically; the in-process
rollback (hub returns non-200 / checksum-install failure) is hard to force
against the real hub and is better covered by a future unit test of
`pv_update_progress_add_downloaded` / `pv_update_progress_report`.

---

## 7. Future: run against a local Pantacor Hub

The remaining external dependencies are the production Hub itself (creds,
network latency, ingest lag on the cloud surface). A local Pantacor Hub, or a
minimal object server stood up by `test.docker.sh` like the appengine/netsim
containers, would make the test hermetic and let it exercise the in-process
`-received` rollback (§6) by returning a mid-stream `401`/`5xx` or a truncated
body on the first attempt. Keep the assertion surface identical so the test body
carries over unchanged when the object source is swapped.

## 8. Integration steps — done

1. ✓ Test dir added at
   `recipes-pv/pantavisor-pvtests/files/remote/lifecycle/download-progress-continuous/`
   (`test.json`, `resources/test`, `output`).
2. ✓ Built `pantavisor-appengine-distro`, then from the unpacked distro dir:
   `./test.docker.sh install-docker` → `./test.docker.sh run
   remote/lifecycle/download-progress-continuous -o` to generate the golden;
   copied `output` back into the git source (CRLF preserved).
3. ✓ Row added to `docs/overview/testing/automated/pvtest-list.md`
   (remote/lifecycle table), marked ✓.
4. ✓ Linked from [`index.md`](index.md).
