# Changelogs

Per-release notes for each meta-pantavisor major-version stream. One file per
major (`CHANGELOG-NNN.md`); inside each file, sections cover every tag in that
stream — release candidates and the final stable — newest first.

| Stream | File |
|---|---|
| 028 | [CHANGELOG-028.md](CHANGELOG-028.md) |
| 029 | [CHANGELOG-029.md](CHANGELOG-029.md) |
| 030 | [CHANGELOG-030.md](CHANGELOG-030.md) |

Each section captures:

- **Downloads** — per-machine binaries with SHA256 (sourced from the
  publicly-published `releases.json`). The stable section committed here carries
  predicted URLs; the hashed copy lives on the S3 accumulator and the GitHub
  Release page.
- **Component versions** — recipe-pinned `SRCREV` deltas vs the previous
  release in the stream, with GitHub `compare` URLs.
- **Changes** — high-level rollup of conventional-commit subjects grouped by
  type (Features / Fixes / CI / Docs / Other), no commit hashes.

## Where the sections live

Release-candidate sections are **not** committed here. They are accumulated onto
a per-major document on S3
(`https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/changelog/CHANGELOG-NNN.md`)
by [`tag-changelogs.yaml`](../.github/workflows/tag-changelogs.yaml) as each RC
is tagged. This repo file is written exactly once per major — by
`.github/scripts/make-changelog.sh --finalize NNN` just before the stable tag —
and [`changelog-gate.yaml`](../.github/workflows/changelog-gate.yaml) blocks the
stable release build if that commit is missing or does not match the S3
document.

See [`docs/overview/ci/changelog.md`](../docs/overview/ci/changelog.md) for the
full flow.
