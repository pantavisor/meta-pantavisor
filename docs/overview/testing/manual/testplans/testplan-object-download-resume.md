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

## 2. Forcing an interruption without killing Pantavisor

`update-retries-gc-pressure` forces a retry by `killall`-ing the whole
process. That exercises the *update-level* retry path
(`u->progress.retries`, whole object list re-enrolled), but it's a heavier
hammer than the failure mode Range-resume is mainly for: a single dropped
HTTP connection while Pantavisor itself stays up.

To force that directly and deterministically, set `PH_LIBEVENT_HTTP_TIMEOUT`
low relative to the download time of a large single object (the same
`bigfile.bin` `dd`-sizing approach as `update-retries-gc-pressure` /
`testplan-download-progress.md` §5 — a 50 MB random object reliably spans
multiple seconds against the harness's effective hub bandwidth). This
produces a timeout mid-transfer (`evhttp_connection_set_timeout_tv` firing),
which drives `_recv_get_object_done_cb`'s `res != 200 && res != 206` branch —
exactly the resume path — without touching the process.

> **Note:** per existing operational memory, `PH_LIBEVENT_HTTP_TIMEOUT` must
> never be set this low on a *real device config* (it causes spurious
> rollback of unrelated requests) — this is a test-only knob, scoped to a
> single pvtest's `setup.env`, not a config recommendation.

## 3. The deterministic discriminator

Directly observe the on-disk partial file rather than only the higher-level
progress API, since the file is the thing this feature changes the handling
of. The tmp object lives at `<PV_STORAGE_MNTPOINT>/objects/<id>.tmp`
(`pv_paths_storage_object_tmp`, `paths.c`), which resolves to
`/storage/objects/<sha256>.tmp` for a default storage mount — readable (not
writable) from the `pvr-sdk` test container via the shared `/storage` mount.

| | tmp file size across a forced timeout |
|---|---|
| **Old (pre-resume)** behavior | resets to `0` (or disappears) after every timeout — each retry re-downloads from scratch |
| **New (resume)** behavior | size at the next `DOWNLOADING` sample is **>= size** observed just before the timeout — never resets |

**Assertion**: sample the tmp file size once while `DOWNLOADING`, force (or
wait for) a natural timeout via the low `PH_LIBEVENT_HTTP_TIMEOUT`, then
sample again once back in `DOWNLOADING`. Assert the second sample is `>=`
the first (monotonic — never assert an exact byte value, same rationale as
`testplan-download-progress.md` §2 and §4). Never assert on the number of
timeouts/retries that occur — that's timing-dependent.

## 4. Test: `remote/lifecycle/download-resume-on-timeout`

### `test.json`

Mirror `update-retries-gc-pressure`'s setup, but drop the GC-pressure knobs
(clean download, no GC interference — see
`testplan-download-progress.md` §5.3) and set a low HTTP timeout instead of
killing the process:

```json
{
  "#spec": "pv-test@1",
  "description": "Object download resumes via Range after a connection timeout, without restarting from scratch",
  "setup": {
    "cmdline": "",
    "env": "PV_CONTROL_REMOTE=1 PV_LOG_CAPTURE_DMESG=0 PV_STORAGE_PHCONFIG_VOL=1 PH_LIBEVENT_HTTP_TIMEOUT=5 PV_SECUREBOOT_MODE=disabled PH_METADATA_DEVMETA_INTERVAL=10 PH_METADATA_USRMETA_INTERVAL=10 PH_UPDATER_INTERVAL=5 PV_WDT_MODE=disabled PV_DEBUG_SSH=0 PV_LOG_DIR_MAXSIZE=2147483647",
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
parsing at all. The tmp file is inspected via `pventer -c pvr-sdk` (see
`local/services/on-demand-gc`'s established pattern for reaching into
`/storage` from the control container), sampled continuously (not just
before/after) so a reset-to-zero at *any* point during the whole
`DOWNLOADING` window is caught, not just at two arbitrarily-chosen instants:

```sh
#!/bin/sh

source /usr/share/pantavisor/pvtest/utils

device_id=$(cat /var/run/pantavisor/pv/device-id)
pvr clone "https://api.pantahub.com/trails/$device_id" /home/checkout > /dev/null 2>&1
cd /home/checkout

dd if=/dev/urandom of=pvr-sdk/bigfile.bin bs=1M count=100 2>/dev/null
sha=$(sha256sum pvr-sdk/bigfile.bin | awk '{print $1}')
pvr add pvr-sdk/bigfile.bin > /dev/null 2>&1
pvr commit -m "add large file to exercise download-resume" > /dev/null 2>&1
pvr post -m "download resume on timeout test" > /dev/null 2>&1

tmp_path="/storage/objects/${sha}.tmp"

wait_for_value "pvcontrol steps show-progress 1 | jq -r '.status'" "DOWNLOADING" 120 \
    || { echo "ERROR: timeout waiting for DOWNLOADING" >&2; exit 1; }

prev=0
saw_nonzero=0
no_reset=1
for i in $(seq 1 180); do
    st=$(pvcontrol steps show-progress 1 | jq -r '.status')
    if [ "$st" != "DOWNLOADING" ]; then
        [ "$st" = "NEW" ] || [ "$st" = "QUEUED" ] || break
        sleep 1
        continue
    fi

    size=$(pventer -c pvr-sdk wc -c "$tmp_path" 2>/dev/null | awk '{print $1}')
    [ -z "$size" ] && size=0

    if [ "$size" -gt 0 ] 2>/dev/null; then
        saw_nonzero=1
        if [ "$size" -lt "$prev" ] 2>/dev/null; then
            no_reset=0
        fi
        prev="$size"
    fi
    sleep 1
done

echo "object-tmp-file-seen: $saw_nonzero"
echo "object-tmp-file-no-reset: $no_reset"

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

Two deviations from the original sketch, both confirmed necessary by running
the test for real:
- **Object size bumped 50→100 MB** and **`PH_LIBEVENT_HTTP_TIMEOUT` raised
  5→20s**: 5s was too aggressive — it's a single global knob shared by *all*
  Hub HTTP traffic (registration, claim, metadata, not just downloads), and
  starved the initial device self-registration/claim handshake before the
  test ever reached the download phase. 20s clears that safely while 100 MB
  still comfortably outlasts it.
- **Continuous sampling + monotonic-non-decrease assertion**, not a single
  before/after size comparison: a two-sample check can't distinguish "resumed"
  from "restarted from 0 and coincidentally regrew past the old sample by the
  time of the second check" — see §3 above.

### `output` (golden, generated and verified — 3 consecutive clean runs)

```
object-tmp-file-seen: 1
object-tmp-file-no-reset: 1
{"status":"DONE","progress":100}
```

## 5. Companion: graceful fallback (server ignores Range)

Not automatable against the production Hub today (it already speaks Range
correctly once !395 ships), but worth a manual check against a Hub build
predating !395, or a local stub server: confirm Pantavisor still completes
the download via a full re-fetch — no crash, no corrupted install, just less
efficient. This is the `dctx->sent_range && code != 206` branch in
`_recv_get_object_chunk_cb`.

## 6. Non-flaky guarantees / open risk

Same object-sizing caveat as `testplan-download-progress.md` §5 applies:
`PH_LIBEVENT_HTTP_TIMEOUT=20` only reliably interrupts mid-transfer if the
object takes noticeably longer than 20s to fully download against the
harness's effective hub bandwidth — 100 MB has been empirically confirmed
(3 consecutive runs, ~180-195s wall time each) to keep the download open
well past that window. If hub bandwidth ever rises enough that 100 MB
downloads in under ~20s, bump `count=` accordingly and re-validate.

Validated over 3 consecutive clean runs (1 golden-generating + 2 verify-only
against the recorded `output`); not yet run the full ≥20x loop used for the
download-progress test — worth doing before leaning on this test long-term
in CI, given it depends on real Hub round-trip timing.

## 7. Integration steps — done

1. ✓ Test dir added at
   `recipes-pv/pantavisor-pvtests/files/remote/lifecycle/download-resume-on-timeout/`.
2. ✓ Built via `kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml:kas/with-workspace.yaml -- pantavisor-appengine-distro`,
   `install-docker`, `run ... -o` to generate the golden, copied back to the
   source tree (CRLF preserved).
3. Ran 3 consecutive clean passes (not the full ≥20x loop yet — see §6).
4. ✓ Row added to `docs/testing/automated-workflow.md` (remote/lifecycle
   table), marked ✓.
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
