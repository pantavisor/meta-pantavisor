# Remote Update Cancel Test Plan

Covers the device honoring an owner-side cancel while a revision is `QUEUED` or
`DOWNLOADING`, and the Hub precondition change that makes such a cancel
possible in the first place.

## 1. What is being tested

- Hub: `PUT /trails/{id}/steps/{rev}/cancel` (owner token) is accepted while the
  step is `NEW`, `QUEUED`, `DOWNLOADING` or `INPROGRESS` (pantahub-base !415). It sets
  `progress.status` to `CANCEL`.
- Device: while `QUEUED`/`DOWNLOADING`, Pantavisor re-reads its own step from the
  Hub on every download tick (6 s) and only then sends that tick's download
  progress PUT, so it never overwrites a cancel it has not read yet. On
  `CANCEL` it aborts in-flight object transfers, keeps the partial `<sha>.tmp`
  objects, reports `CANCEL` with `status-msg` `Cancelled as requested by owner`,
  and returns to idle on the previous revision.
- Non-adherence stays visible: the device progress PUT is unconditional on the
  Hub, so a device that ignores the cancel overwrites `CANCEL` with
  `DOWNLOADING`/`INPROGRESS`. The test reads the step back from the Hub after
  the device went idle to prove that did not happen. The same unconditional
  PUT means a cancel landing in the short window between the device's poll
  and its progress PUT is overwritten; the owner (and the test) re-issues it.

Out of scope: a cancel (or the older `wontgo`) set on the Hub while `INPROGRESS`/
`TESTING` is never read by the device; it only stops a device that lost track of the
step from retrying it, which cannot be driven from the appengine harness.

## 2. Forcing a wide cancel window

Same recipe as `download-resume-on-timeout`: a 100 MB `/dev/urandom` object and
`PH_UPDATER_DOWNLOAD_RATE_LIMIT=1048576` give ~100 s of `DOWNLOADING`.
The cancel is only sent once `>5 MiB` of the partial object is on disk, so the
abort lands mid-transfer with real bytes to keep.

## 3. Test: `remote/lifecycle/download-cancel-mid-transfer`

Steps and discriminators printed by `resources/test`:

1. post the revision, wait for `DOWNLOADING` → `partial-object-on-disk-before-cancel: 1`
2. owner cancel via curl with the bearer from `$HOME/.pvr/auth.json` →
   `hub-cancel-http-code: 200` (a `400` here means the Hub still has the
   `NEW`-only precondition)
3. `pvcontrol steps show-progress $rev` reaches `CANCEL`; if the Hub shows
   `DOWNLOADING` again after 15 s the cancel was overwritten by the progress
   PUT of the same tick and is re-issued (up to 4 attempts, logged to stderr)
4. `pantahub.state` back to `idle`, `pantavisor.status` `READY`,
   `pantavisor.revision` unchanged → `still-on-previous-revision: 1`
5. partial size after cancel `>=` size before → `partial-object-kept: 1`
6. after a 10 s grace for any in-flight PUT, `GET /trails/{id}/steps/{rev}` as
   owner → `hub-step-status: CANCEL`

## 4. Manual variant on a real device

```sh
pvr post -m "big" https://api.pantahub.com/trails/<device-id>
# once `pvr device status <nick>` shows DOWNLOADING:
curl -X PUT -H "Authorization: Bearer $(jq -r 'first(.tokens[])["access-token"]' ~/.pvr/auth.json)" \
    https://api.pantahub.com/trails/<device-id>/steps/<rev>/cancel
pvr device status <nick>     # expect CANCEL, then the device back at the old rev
ls /storage/objects/*.tmp    # partial object still there
```

## 5. Status

- Golden `output` is hand-written: it can only be regenerated once !415 is
  deployed on `api.pantahub.com` and the device image carries
  `feature/remote-update-cancel`.
