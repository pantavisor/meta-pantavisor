---
sidebar_position: 7
---
# Per-release CHANGELOG

Each meta-pantavisor release ships with a section in
[`CHANGELOG/CHANGELOG-NNN.md`](https://github.com/pantavisor/meta-pantavisor/tree/master/CHANGELOG) summarizing what changed
relative to the previous release in the same stream. The format is modeled on
the [Kubernetes changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.36.md).

## Layout

| Piece | Path |
|---|---|
| Generator | [`.github/scripts/make-changelog.sh`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/make-changelog.sh) |
| Component map (JSON) | [`.github/scripts/components.json`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/components.json) |
| CI workflow | [`.github/workflows/tag-changelogs.yaml`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/workflows/tag-changelogs.yaml) |
| Output | `CHANGELOG/CHANGELOG-<MAJOR>.md` (e.g. `CHANGELOG-028.md`) |

The generator is a single bash script using `git`, `curl`, `jq`, and `awk`.
It runs both **in CI** (after the tag build completes) and **locally** (when
you want to preview a section, regenerate, or run the pre-tag flow).

## What goes into a section

For tag `T` (e.g. `028-rc7`):

1. **Downloads** — every machine entry under `release-candidate.<T>` (or
   `stable.<T>`) in
   `https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/releases.json`,
   rendered as a table with image, pvexports, BSP, and SDK download links plus
   the first 12 chars of each `sha256`. Cells with empty URLs or hashes render
   as `—`. **In pre-tag mode** (see below) `releases.json` doesn't yet have an
   entry for `<T>`; the script falls back to the previous tag's entry and
   substitutes `<T>` in the URLs, emitting "Pending" links and an italic note
   above the table. The links 404 until the build pipeline uploads the
   artifacts to S3, after which they activate at exactly those URLs. SHA256
   columns are blank in predicted mode (the hashes aren't known yet).
2. **Component versions** — for every recipe in
   [`components.json`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/components.json), the `SRCREV` is
   read at the source rev (HEAD in pre-tag mode, the tag in historical mode)
   and at the previous tag in the stream. Each row shows previous SHA, current
   SHA, and a `compare` URL when they differ.
3. **Changes** — `git log --no-merges --format=%s <prev>..<source>` parsed as
   Conventional Commits. Subjects are grouped under `### Features` / `### Fixes`
   / `### CI` / `### Docs` / `### Other`. Hashes are dropped. Aliases:
   `feature` → Features, `doc` → Docs, `build` → CI. `chore`, `style`,
   `changelog`, and `changelogs` subjects are dropped (the last two prevent
   the autoadd commit from feeding back into itself on re-runs).

## Modes

The script auto-detects which mode to run in based on whether the tag exists:

| Mode | Triggered when | Source rev | Release date | Auto-commit? |
|---|---|---|---|---|
| **pre-tag** | `<TAG>` does **not** exist as a git tag | `HEAD` | today | yes (default) |
| **historical** | `<TAG>` exists as a git tag | `<TAG>` | the tag's commit date | no |

The pre-tag mode is the production flow: you generate the section just before
tagging, so the changelog file is part of the very commit that gets tagged.
The historical mode is for backfill, regeneration, or local previews of past
releases.

## Previous-tag resolution

For tag `T` in major `M`:

- `T == M` (final stable): previous = highest `M-rc*`.
- `T == M-rcN` and `N > 1`: previous = `M-rc<N-1>` (or the immediate predecessor in `sort -V` order across the stream).
- `T == M-rc1`: previous = the most recent prior stable (e.g. `M-1`).

Implementation walks `git tag -l "${M}-rc*"` plus all `^0+[0-9]*$` (stable)
tags, sorts with `sort -V`, and picks the highest tag less than `T`.

## Release flow

There are two supported flows. The **automated flow** is the default; the
**local pre-tag flow** is still available for releases where you want the
changelog file inside the tagged commit itself.

### Automated flow (default)

1. Decide on the tag name (e.g. `028-rc8`) and tag HEAD of `master`:
   ```sh
   git tag 028-rc8
   git push origin master 028-rc8
   ```
2. The push triggers `tag-scarthgap.yaml`, which builds every machine and
   uploads the artifacts to S3.
3. On completion, `tag-changelogs.yaml` fires via `workflow_run`. It:
   - Checks out `master` with full history
   - Runs `make-changelog.sh <TAG>` in **historical mode** — writes the
     `CHANGELOG/CHANGELOG-<MAJOR>.md` file but does not auto-commit
   - Renders the section via `make-changelog.sh --stdout <TAG>` to a file
   - Creates (or updates) the GitHub Release for `<TAG>` with that file as
     the body — `gh release create --notes-file …` / `gh release edit
     --notes-file …`. **No build artifacts are attached** — they live on S3
     and the changelog Downloads table links to them
   - Opens a PR back to `master` titled
     `changelogs(<TAG>): autoadd changelog`, with the updated CHANGELOG file
     as the only diff. Authored using the existing
     `secrets.PANTAVISOR_TAG_SYNC_TOKEN` PAT (so the resulting PR can
     trigger downstream workflows if desired).
4. Review and merge the PR. The release page is already populated regardless
   of whether the PR is merged — the two are independent outputs.

If S3 wasn't ready when the workflow first fired (rare race), re-run the
workflow manually:

```sh
gh workflow run tag-changelogs.yaml -f tag=028-rc8
```

The release notes and PR will be regenerated from the now-current
`releases.json`.

### Local pre-tag flow (optional)

Use this when you want the changelog file to be part of the tagged commit
itself — for example, when shipping a stable release where the document
should be reachable at the tag's tree:

```sh
# 1. Make sure HEAD is the commit you want to tag.
git status
git log -1

# 2. Run the generator with the upcoming tag name. In pre-tag mode (tag
#    doesn't exist yet) this writes the new section to
#    CHANGELOG/CHANGELOG-028.md and creates a new commit on top of HEAD with
#    message "changelogs(028-rc8): autoadd changelog". The Downloads table
#    is populated with predicted URLs (see "Modes" below).
./.github/scripts/make-changelog.sh 028-rc8

# 3. Inspect the generated section and the commit.
git show HEAD

# 4. Tag the autoadd commit and push.
git tag 028-rc8
git push origin master 028-rc8
```

The CI flow still runs after the tag push: `tag-changelogs.yaml` will
generate the historical-mode section (with real download SHA256s) and open
a PR overwriting the predicted section with the live one. Merge that PR to
update master with real hashes; the tagged commit's section keeps the
predictions.

## Flag reference

```
make-changelog.sh <TAG>              # write file; auto-commit if pre-tag mode
make-changelog.sh --no-commit <TAG>  # write file but never commit
make-changelog.sh --stdout <TAG>     # print section to stdout, no file write, no commit
```

`--no-commit` is the right choice for backfill loops or any time you want to
batch multiple tags into one commit.

## Idempotency

Re-running on the same tag is safe: the prior `## v<tag>` section is replaced
rather than duplicated, the file header is preserved, and the auto-commit
step is skipped if the file content didn't change.

The autoadd commits themselves (`changelogs(...)`) are filtered out of the
Changes section, so re-running pre-tag mode after committing once won't pull
the autoadd commit back in.

## Backfill

To populate `CHANGELOG/CHANGELOG-028.md` from already-tagged releases:

```sh
for tag in $(git tag -l "028-rc*" "028" | sort -V); do
  ./.github/scripts/make-changelog.sh --no-commit "$tag"
done
git add CHANGELOG/CHANGELOG-028.md
git commit -m "changelogs(028): backfill"
```

## Adding a new component

Append an entry to [`components.json`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/components.json):

```json
{
  "name": "<name>",
  "recipe_glob": "<recipe-glob>",
  "branch": "<branch>",
  "repo_org": "<github-org>"
}
```

`make-changelog.sh` reads this file via `jq` and picks up the new entry on
the next run.

## When `releases.json` is missing or stale

If `<TAG>` has no entry in `releases.json` (pre-tag mode by design, or the
upload step failed for an existing tag), the script falls back to the
**previous tag's** entry and substitutes `<TAG>` in the URLs. The result is
a "Pending" download table that mirrors the predecessor's machine list — the
URLs are deterministic (S3 path = `meta-pantavisor/<TAG>/<machine>/...`) so
the predicted links activate exactly at upload time. The note above the
table flags this clearly.

If neither the current tag nor the previous tag has entries (e.g. very early
in a major's history with no predecessor in the stream and no prior major
to fall back on), the section renders as
`_(no artifacts recorded in releases.json yet, and no previous release to predict from)_`.
The script does not fail in either case.

Note: BSP and SDK URLs from the predecessor carry forward unchanged in their
filename portion (those filenames don't embed the tag), so the predicted URL
will be correct as long as the recipe's BSP/SDK output naming is stable
across the release. If a release adds or removes a BSP/SDK output for a
machine, regenerate the section in historical mode after the build to
correct it.
