---
sidebar_position: 6
---
# Tag sync: meta-pantavisor → pantavisor

When a release tag is pushed to `meta-pantavisor`, a workflow mirrors that tag
to the upstream [pantavisor/pantavisor](https://github.com/pantavisor/pantavisor)
repo, pointing at the exact `SRCREV` recorded in
`recipes-pv/pantavisor/pantavisor.inc` (`PANTAVISOR_SRCREV`).

This gives upstream a marker linking each pantavisor commit back to the BSP
release that shipped it.

## Mechanics

| Piece | Path |
|-------|------|
| Workflow | `.github/workflows/tag-sync-pantavisor.yaml` |
| Script   | `.github/scripts/sync-pantavisor-tag.sh` |
| Trigger  | `push: tags: ['0*', '*-rc*']` (mirrors `tag-scarthgap.yaml`) |
| Tag name | identical to the meta-pantavisor tag (no prefix) |
| Tag type | lightweight (just a ref) |
| Tag target | RC: the `SRCREV`. Stable `0NN`: a finalize commit on top of the `SRCREV` |

The workflow runs in parallel with `tag-scarthgap.yaml` and is independent of
the build matrix — sync failures do not block image builds, and image-build
failures do not block tag sync.

## What the script does

1. Parses `PANTAVISOR_SRCREV` from `recipes-pv/pantavisor/pantavisor.inc`.
2. Verifies the SHA is reachable on `pantavisor/pantavisor` (fails if the
   recipe is pinned to an unpublished commit).
3. Checks whether the tag already exists upstream:
   - **Absent** → creates `refs/tags/$TAG_NAME` at the SRCREV. For a stable
     `0NN` tag it first [commits the changelog](#stable-tags).
   - **Present at the same SHA** → no-op (idempotent re-runs are safe). A stable
     tag also counts as in sync when it points at the finalize commit directly
     on top of the SRCREV.
   - **Present at a different SHA** → fails. The script never overwrites an
     existing tag.
4. Writes a one-line summary to `$GITHUB_STEP_SUMMARY`.

## Stable tags

pantavisor's `changelog-gate` rejects a stable tag whose commit lacks
`CHANGELOG/CHANGELOG-<MAJOR>.md`. So for a stable `0NN` tag the script clones
`pantavisor/pantavisor` at the SRCREV, runs `make-changelog.sh --finalize 0NN`
(one commit that only adds that file) and pushes that commit as the tag. The
source is identical to the SRCREV, and nothing is pushed to a branch, so
`master` protection does not apply.

Push the stable meta-pantavisor tag only after every RC's `tag-changelogs`
workflow in pantavisor has finished: `--finalize` reads the S3 accumulator and
the gate checks that all RC sections are in it.

The finalize commit is reachable only through the tag. `master` does not carry
`CHANGELOG-0NN.md`.

## Authentication

The workflow needs to push refs to a repo outside meta-pantavisor, so the
default `GITHUB_TOKEN` is not enough.

Required: a classic Personal Access Token with the `repo` scope, stored as the
repo secret `PANTAVISOR_TAG_SYNC_TOKEN`.

### Setup (one-time)

1. As a release-manager or service account that has write access to
   `pantavisor/pantavisor`:
   - GitHub → **Settings** → **Developer settings** → **Personal access tokens**
     → **Tokens (classic)** → **Generate new token (classic)**.
   - Scope: `repo` (full control of private repositories — required for
     pushing tags).
   - Pick the longest expiry your org policy allows.
2. In `meta-pantavisor`:
   - **Settings** → **Secrets and variables** → **Actions** → **New repository
     secret**.
   - Name: `PANTAVISOR_TAG_SYNC_TOKEN`. Value: the token from step 1.
3. Record the token's expiry date below so it gets rotated before it lapses:

   | Token | Expires |
   |-------|---------|
   | `PANTAVISOR_TAG_SYNC_TOKEN` | _fill in on rotation_ |

### Rotation

Replace the secret value before the recorded expiry. The workflow only reads
the secret at run time — there is no caching to invalidate.

## Downstream: changelog and release in pantavisor

Because the tag ref is created with a **PAT** (`PANTAVISOR_TAG_SYNC_TOKEN`)
rather than the default `GITHUB_TOKEN`, the synced tag triggers workflows in
`pantavisor`. In particular it fires `pantavisor`'s
`.github/workflows/tag-changelogs.yaml`, which:

1. Generates `CHANGELOG/CHANGELOG-<MAJOR>.md` for the tag (version line plus
   categorized Conventional-Commits changes since the previous tag) and opens a
   PR back to `master`.
2. Creates (or updates) the GitHub Release for the tag with that section as its
   body.

This is the source-repo counterpart of meta-pantavisor's own
[changelog generator](changelog.md). It does **not** render the Downloads or
multi-component SRCREV sections — those are aggregation-layer concepts that do
not apply to the single pantavisor source repo.

Note that the pantavisor-side flow still opens a changelog PR per tag. The
meta-pantavisor side no longer does: RC sections are accumulated on an S3
document and the repo `CHANGELOG/CHANGELOG-<MAJOR>.md` is committed once per
major (at stable), gated by `changelog-gate.yaml`. See
[changelog.md](changelog.md).

For the changelog PR to trigger CI, `pantavisor` needs its own
`PANTAVISOR_TAG_SYNC_TOKEN` repo secret (same kind of PAT as above, with write
access to `pantavisor/pantavisor`). The GitHub Release step uses the built-in
`GITHUB_TOKEN`.

## Recovering from a conflict

If the upstream tag already exists at a different SHA, the workflow exits
non-zero with both SHAs in the log. Common causes:

- `PANTAVISOR_SRCREV` in `pantavisor.inc` was bumped after the upstream tag was created manually.
- An earlier sync ran with a recipe that pointed at a different commit.

To recover, decide which SHA is correct:

- **Upstream tag is correct** — bump `PANTAVISOR_SRCREV` in `pantavisor.inc` to match, retag
  meta-pantavisor.
- **Recipe is correct** — delete the upstream tag, then re-run the workflow:

  ```
  gh api -X DELETE repos/pantavisor/pantavisor/git/refs/tags/<TAG>
  gh workflow run tag-sync-pantavisor.yaml --ref <TAG>
  ```

Never resolve a conflict by force-moving the upstream tag from the script —
moving a published tag rewrites history visible to anyone who already fetched
it.

## Testing the workflow

Push a throwaway tag from a feature branch:

```
git tag 999-rc-syncTest
git push origin 999-rc-syncTest
```

After the workflow finishes, verify the tag exists upstream:

```
gh api repos/pantavisor/pantavisor/git/refs/tags/999-rc-syncTest
```

Clean up:

```
git push --delete origin 999-rc-syncTest
gh api -X DELETE repos/pantavisor/pantavisor/git/refs/tags/999-rc-syncTest
```
