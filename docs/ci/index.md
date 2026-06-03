---
title: "CI"
description: "CI pipeline for meta-pantavisor: machine matrix, release builds, tag sync, and docs publishing."
sidebar_position: 6
---

# CI

Documentation for the meta-pantavisor CI system: how workflows are organized, how machines and builds are driven from `machines.json`, and how releases and docs are published.

## Topics

1. [Overview](overview.md) — workflow map showing how tag pushes trigger sync, release builds, pvtest runs, and artifact uploads
2. [Machines](machines.md) — the `.github/machines.json` schema and how to add or modify a machine; always run `makeworkflows` after editing
3. [Builds](builds.md) — per-machine build workflows, sstate sharing, S3 artifact layout, and badge generation
4. [Status](status.md) — reading build status badges and CI run summaries
5. [Tag Sync](tag-sync.md) — how `meta-pantavisor` tags are mirrored to `pantavisor/pantavisor` and the PAT setup required
6. [Changelog](changelog.md) — per-release `CHANGELOG-NNN.md` generator: format, tag conventions, and regen procedure

## Key Rule

Always run `.github/scripts/makeworkflows` after editing `.github/machines.json`. Commit `machines.json` and the generated workflow files together.
