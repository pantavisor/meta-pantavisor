---
sidebar_position: 1
---
# CI Overview

The CI system builds Yocto images for all supported machines, runs integration tests, mirrors release tags, and publishes artifacts to S3. All behavior is driven from a single source of truth — `.github/machines.json` — from which most workflow files are generated.

## Workflow Map

```
TAG PUSH  (0*  or  *-rc*)
  tag-scarthgap.yaml
    ├── sync     → sync-pantavisor.yaml       mirror tag to pantavisor/pantavisor
    └── release  → release.yaml (after sync)
                    ├── build × N machines    → buildkas-upload.yaml  (kas build + S3 upload)
                    ├── pvtest-local          → call-pvtests.yaml
                    ├── pvtest-remote         → call-pvtests.yaml     (after local)
                    └── summary                 upload per-machine badges to S3

  tag-changelogs.yaml  (workflow_run, fires after tag-scarthgap completes)
    └── changelog       render CHANGELOG-NNN.md, update GitHub Release, open PR to master

  tag-docs-scarthgap.yaml  (workflow_run, fires after tag-scarthgap completes)
    └── build-docs      kas build -c create_pantacor_docs pantavisor-starter → upload tarball to S3


ON PUSH  (master)
  onpush-scarthgap.yaml
    └── build × onpush machines  → buildkas-target.yaml  (kas build, artifacts only)


MANUAL  (workflow_dispatch)
  manual-scarthgap.yaml
    └── build × all manual machines  → buildkas-target.yaml

  manual-pvtests.yaml
    ├── build docker-x86_64-scarthgap  → buildkas-target.yaml
    └── start-pvtest                   → call-pvtests.yaml


SCHEDULED
  schedule-pvtests.yaml       daily 02:00
    ├── build docker-x86_64-scarthgap  → buildkas-target.yaml
    ├── local                          → call-pvtests.yaml
    └── remote                         → call-pvtests.yaml  (after local)

  schedule-updates.yaml       every 8 h
    └── check-and-update   bump SRCREVs via update-components.sh, open PR if changed

  schedule-updatemachines.yaml  every 8 h + 15 min
    └── updaterelease      run makemachines + makeworkflows, open PR if changed
```

## Workflow Files

| File | Trigger | Role |
|---|---|---|
| `tag-scarthgap.yaml` | tag push | Orchestrator: sync → release |
| `release.yaml` | `workflow_call` | Build matrix + pvtests + badge upload |
| `tag-changelogs.yaml` | `workflow_run` after tag-scarthgap | Changelog generation and GitHub Release |
| `tag-docs-scarthgap.yaml` | `workflow_run` after tag-scarthgap | Build combined docs tarball via `pantavisor-docs` class, upload to S3 |
| `sync-pantavisor.yaml` | `workflow_call` | Mirror tag to pantavisor/pantavisor |
| `onpush-scarthgap.yaml` | push to master | Build matrix for onpush machines |
| `manual-scarthgap.yaml` | `workflow_dispatch` | Build any machine on demand |
| `manual-pvtests.yaml` | `workflow_dispatch` | Build + run pvtests on demand |
| `schedule-pvtests.yaml` | cron daily 02:00 | Nightly build + full pvtest run |
| `schedule-updates.yaml` | cron every 8 h | SRCREV bump PRs |
| `schedule-updatemachines.yaml` | cron every 8 h + 15 min | kas config + workflow regen PRs |
| `buildkas-upload.yaml` | `workflow_call` | Reusable: build + S3 upload (tag builds) |
| `buildkas-target.yaml` | `workflow_call` | Reusable: build + GitHub artifacts (dev builds) |
| `call-pvtests.yaml` | `workflow_call` | Reusable: run pvtests suite |

## Scripts

| Script | Purpose |
|---|---|
| `makemachines` | Flatten KAS config fragments into `kas/build-configs/release/*.yaml` |
| `makeworkflows` | Regenerate `onpush-*`, `manual-*`, and `release.yaml` from `machines.json` |
| `make-tag-matrix.py` | Generate `release.yaml` (build matrix + pvtests + summary) |
| `make-onpush-matrix.py` | Generate `onpush-scarthgap.yaml` |
| `make-manual-dispatch.py` | Generate `manual-scarthgap.yaml` |
| `makecommit` | Audit layer changes and draft PR description |
| `update-components.sh` | Fetch latest SRCREVs for tracked components |
| `upload.sh` | Push build artifacts and update `releases.json` on S3 (machine `devices` entries) |
| `upload-docs.py` | Upload docs tarball to GitHub Release (`upload-asset` sub-command); separate `trigger-ingest` sub-command exists but the workflow notifies `docs.pantavisor` via a direct `curl` `repository_dispatch` instead |
| `upload-badges` | Write per-machine badge JSON to S3 after a tag build |
| `sync-pantavisor-tag.sh` | Push the tag to `pantavisor/pantavisor` via PAT |
| `make-changelog.sh` | Render a CHANGELOG section for a given tag |
| `update-readme-board.py` | Regenerate the workflow status table in `docs/ci/status.md` |

## Runners and Container

All builds run on self-hosted runners inside the `ghcr.io/pantacor/kas/kas:next-v7` container. Shared sstate-cache and download directories are mounted at `/shared/sstate` and `/shared/dldir` to speed up incremental builds. Summary and badge jobs run on GitHub-hosted `ubuntu-latest`.

## Related docs

- [machines.md](machines.md) — `machines.json` schema, adding boards, workflow generation
- [builds.md](builds.md) — build engines, artifact types, S3 layout, pvtests
- [changelog.md](changelog.md) — changelog generator and release notes
- [tag-sync.md](tag-sync.md) — tag mirror to pantavisor/pantavisor
- [status.md](status.md) — live CI status badges
- [versioning.md](versioning.md) — dynamic DISTRO_VERSION generation
