---
sidebar_position: 7
---
# Per-release CHANGELOG

Each meta-pantavisor release gets a section summarizing what changed relative
to the previous release in the same stream. The format is modeled on the
[Kubernetes changelog](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.36.md).

Where those sections live depends on the tag:

- **Release candidates** (`0NN-rcN`) are accumulated onto a per-major document
  on S3 (the [S3 accumulator](#s3-accumulator)). They are never committed to
  `master`.
- **The final stable** (`0NN`) is committed once, into
  [`CHANGELOG/CHANGELOG-<MAJOR>.md`](https://github.com/pantavisor/meta-pantavisor/tree/master/CHANGELOG),
  by a maintainer running `make-changelog.sh --finalize` just before tagging.
  A [CI gate](#the-stable-release-gate) blocks the stable release build if that
  commit is missing or stale.

Every tag — RC and stable — also gets a GitHub Release whose body is the
rendered section.

## Layout

| Piece | Path |
|---|---|
| Generator | [`.github/scripts/make-changelog.sh`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/make-changelog.sh) |
| Component map (JSON) | [`.github/scripts/components.json`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/scripts/components.json) |
| Accumulate + release notes | [`.github/workflows/tag-changelogs.yaml`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/workflows/tag-changelogs.yaml) |
| Stable-release gate | [`.github/workflows/changelog-gate.yaml`](https://github.com/pantavisor/meta-pantavisor/blob/master/.github/workflows/changelog-gate.yaml) |
| S3 accumulator | `https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/changelog/CHANGELOG-<MAJOR>.md` |
| Committed output | `CHANGELOG/CHANGELOG-<MAJOR>.md` (written only at stable) |

The generator is a single bash script using `git`, `curl`, `jq`, and `awk`.
It runs **in CI** on every tag (accumulate + release notes) and **locally**
when you preview a section or run `--finalize` before a stable tag.

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
   the `changelogs(...)` commits from feeding back into the changelog on
   re-runs).

## Modes

The script auto-detects which mode to run in based on whether the tag exists:

| Mode | Triggered when | Source rev | Release date | Downloads | Auto-commit? |
|---|---|---|---|---|---|
| **pre-tag** | `<TAG>` does **not** exist as a git tag | `HEAD` | today | predicted URLs | yes (default) |
| **historical** | `<TAG>` exists as a git tag | `<TAG>` | the tag's commit date | real hashes from `releases.json` | no |

- **historical** is what CI runs on every tag (`tag-changelogs.yaml`). It
  writes the file and the workflow uploads it to the [S3
  accumulator](#s3-accumulator) — no commit.
- **pre-tag** is local-only now, reached through `--finalize` (see the
  [stable flow](#stable-flow)). It renders the stable section with predicted
  download URLs — the build that produces the real hashes runs *after* the
  tag — and auto-commits.

## Previous-tag resolution

For tag `T` in major `M`:

- `T == M` (final stable): previous = highest `M-rc*`.
- `T == M-rcN` and `N > 1`: previous = `M-rc<N-1>` (or the immediate predecessor in `sort -V` order across the stream).
- `T == M-rc1`: previous = the most recent prior stable (e.g. `M-1`).

Implementation walks `git tag -l "${M}-rc*"` plus all `^0+[0-9]*$` (stable)
tags, sorts with `sort -V`, and picks the highest tag less than `T`.

## S3 accumulator

One rolling Markdown document per major stream lives at:

```
https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/changelog/CHANGELOG-<MAJOR>.md
```

`tag-changelogs.yaml` refreshes it on **every** tag: it seeds a checkout from
the current S3 copy, runs `make-changelog.sh --no-commit <TAG>` (historical
mode) to merge in the tag's section newest-first, then `aws s3 cp`s the result
back. This is the always-current cross-RC view — RC sections never reach
`master`. It is also the base that `--finalize` pulls from at stable, and the
reference the [stable-release gate](#the-stable-release-gate) diffs against.

## Release flow

### RC flow

1. Tag HEAD of `master` and push:
   ```sh
   git tag 030-rc3
   git push origin master 030-rc3
   ```
2. The push triggers `tag-scarthgap.yaml` (build every machine, upload
   artifacts + `releases.json` to S3). The `changelog-gate` job passes
   instantly for RC tags.
3. On completion `tag-changelogs.yaml` fires: merges `## v030-rc3` into the
   [S3 accumulator](#s3-accumulator) and creates/updates the GitHub Release
   for `030-rc3` with the rendered section as its body. **Nothing is committed
   to `master`.**

If S3 wasn't ready when the workflow first fired (rare race), re-run it:

```sh
gh workflow run tag-changelogs.yaml -f tag=030-rc3
```

### Stable flow

Do this once, after every RC's release workflow has finished (so the S3
accumulator is complete):

```sh
# 1. HEAD of master is the commit you want to tag.
git switch master && git pull

# 2. Pull the accumulated changelog into the repo and add the stable
#    "## v030" section. Downloads use predicted URLs — the build that
#    produces real hashes runs after the tag. Commits
#    "changelogs(030): finalize 030 changelog". Errors if 030 is already tagged.
./.github/scripts/make-changelog.sh --finalize 030

# 3. Review the commit: it should touch only CHANGELOG/CHANGELOG-030.md and
#    contain every "## v030-rcN" section plus a new "## v030".
git show HEAD

# 4. Push the finalize commit, THEN tag.
git push origin master
git tag 030
git push origin 030
```

The `030` push runs `changelog-gate` first (see below). Once it passes the
build proceeds; on completion `tag-changelogs.yaml` refreshes the S3
accumulator and the GitHub Release for `030` with real download hashes. The
committed `CHANGELOG/CHANGELOG-030.md` keeps its predicted URLs — the hashed
copy lives on the S3 accumulator and the Release page.

## The stable-release gate

`changelog-gate.yaml` runs as a `tag-scarthgap.yaml` job that `release` depends
on. RC tags pass through untouched. For a stable `0NN` tag it fails the run —
skipping the entire build — unless the tagged commit's
`CHANGELOG/CHANGELOG-<MAJOR>.md`:

| Check | Fix on failure |
|---|---|
| has a `## v<MAJOR>` stable section | run `make-changelog.sh --finalize <MAJOR>` |
| has a `## v<MAJOR>-rcN` section for every `<MAJOR>-rc*` git tag | re-run `--finalize` after all RC release workflows finish |
| its RC sections match the S3 accumulator byte-for-byte | re-run `--finalize` (its base was stale) and re-push before tagging |

The `--finalize` commit must be pushed to `master` **before** the stable tag,
otherwise the tagged tree won't contain it and the gate fails on the first
check.

## Flag reference

```
make-changelog.sh <TAG>               # write file; auto-commit if pre-tag mode
make-changelog.sh --no-commit <TAG>   # write file but never commit (CI uses this)
make-changelog.sh --stdout <TAG>      # print section to stdout, no file write, no commit
make-changelog.sh --finalize <MAJOR>  # seed the repo file from the S3 accumulator, add the
                                      # "## v<MAJOR>" stable section, commit
                                      # "changelogs(<MAJOR>): finalize <MAJOR> changelog"
```

`--finalize` is the only path that writes `CHANGELOG/CHANGELOG-<MAJOR>.md` in
the repo now. Point `CHANGELOG_S3_URL_BASE` at a `file://` directory to test it
without S3.

## Idempotency

Re-running on the same tag is safe: the prior `## v<tag>` section is replaced
rather than duplicated, the file header is preserved, and the auto-commit
step is skipped if the file content didn't change.

The `changelogs(...)` commits themselves are filtered out of the Changes
section, so re-running `--finalize` after committing once won't pull the
finalize commit back in.

## Regenerating a section

To re-render one tag's section (e.g. after fixing `releases.json` or
`components.json`), run it in historical mode and re-publish the S3
accumulator:

```sh
URL=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/changelog/CHANGELOG-030.md
curl -sfL -o CHANGELOG/CHANGELOG-030.md "$URL"
./.github/scripts/make-changelog.sh --no-commit 030-rc2
# inspect CHANGELOG/CHANGELOG-030.md, then re-upload:
#   aws s3 cp CHANGELOG/CHANGELOG-030.md s3://$AWS_S3_BUCKET/changelog/CHANGELOG-030.md
```

or just `gh workflow run tag-changelogs.yaml -f tag=030-rc2` and let CI do it.

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
