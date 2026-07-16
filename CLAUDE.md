# meta-pantavisor

Yocto/OpenEmbedded layer for building Pantavisor-based BSP images for embedded Linux systems. Provides recipes, BitBake classes, and KAS configurations for building complete initramfs + container images.

## Key Components

| Component | Description |
|-----------|-------------|
| `kas/` | KAS configuration fragments (machines, platforms, Yocto releases, workspace overlay) |
| `recipes-pv/pantavisor/` | Core Pantavisor runtime recipe |
| `recipes-pv/images/` | BSP, initramfs, appengine image recipes |
| `recipes-containers/pv-examples/` | Example containers for xconnect service mesh testing |
| `classes/pvbase.bbclass` | Defines `PANTAVISOR_FEATURES` variable and defaults |
| `classes/container-pvrexport.bbclass` | Container pvrexport packaging |
| `.github/machines.json` | CI machine configurations — edit before regenerating workflows |
| `CHANGELOG/` | Per-major-version release notes (`CHANGELOG-NNN.md`); generated from tag pushes |


## Documentation Structure

`docs/` is split into two top-level groups, each a sidebar category. Which one a
new document belongs to depends on its audience:

| Directory | Content type |
|-----------|-------------|
| `docs/getting-started/` | **Using Pantavisor**, independent of this layer — install/flash guides (`how-to-install/`, incl. `boards/`), app development (`develop/`), device operation (`operate/`), plus `start/`, `migrate/`, `security/`, `benchmarks/`, `solutions/`, `troubleshooting/`, `licensing/`, `community/` |
| `docs/overview/` | **Reference for the meta-pantavisor layer itself** — architecture, build system, and build guide as flat `overview/*.md`, with `examples/`, `testing/` (test plans under `testplans/`), and `ci/` as subdirectories |

Rule of thumb: if it is about building or contributing to *this layer*, it goes
in `overview/`; if it is about running Pantavisor on a device, it goes in
`getting-started/`. Ordering within each group is set by `_category_.json` and
`sidebar_position` front matter; `overview/index.md` carries a hand-ordered
topic list, so add new `overview/` pages there too.

Key documents:
- [docs/overview/pantavisor-development.md](docs/overview/pantavisor-development.md) — local source development with workspace overlay
- [docs/overview/get-started.md](docs/overview/get-started.md) — first build guide
- [docs/overview/manifest-audit.md](docs/overview/manifest-audit.md) — rootfs manifest audit (`pv-manifest-audit` / `pv-manifest-strict`)
- [docs/overview/testing/development-workflow.md](docs/overview/testing/development-workflow.md) — manual appengine testing during development
- [docs/overview/testing/automated-workflow.md](docs/overview/testing/automated-workflow.md) — structured testing with test.docker.sh (valgrind, CI, todo list)
- [docs/overview/ci/tag-sync.md](docs/overview/ci/tag-sync.md) — meta-pantavisor → pantavisor tag-sync workflow and PAT setup
- [docs/overview/ci/changelog.md](docs/overview/ci/changelog.md) — per-release CHANGELOG generator, format, and regen procedure

## Key Pitfalls

**`PANTAVISOR_FEATURES` operator**: Never use `+=` in distro includes — it clobbers `??=` defaults from `pvbase.bbclass`. Always use `:append`:
```bitbake
# WRONG — silently drops defaults (xconnect, pvcontrol, rngdaemon, etc.)
PANTAVISOR_FEATURES += "appengine"
# CORRECT
PANTAVISOR_FEATURES:append = " appengine"
```

**SRCREV bumps**: Always verify the commit hash against the actual remote — squash merges rewrite hashes. Update `PKGV` to match the latest tag reachable from the new SRCREV.

**machines.json**: Always run `.github/scripts/makeworkflows` after editing `.github/machines.json`. Commit machines.json and the generated workflow files together.

## Development Guidelines

- **Pull requests**: Open as drafts (`gh pr create --draft`) while still iterating. Note that the build/test matrix in `onpush-scarthgap.yaml` is gated `if: needs.check-draft.outputs.is_draft != 'true'`, so **CI does not run on drafts** — a draft only ever shows the cheap `check-draft`/`summary` jobs. To get real CI feedback you must `gh pr ready`. When promoting, keep a background monitor on the PR (`gh pr checks <n>`) that reports a failing build back to the developer here.
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) v1.0.0
- **Kconfig changes**: Run `.github/scripts/makemachines` after modifying Kconfig
- **Storage state**: Use fresh storage volumes when testing pvtx.d changes (`docker volume rm storage-test`)
- **API testing**: Use `pvcurl`/`pvcontrol` (not `curl`) inside appengine containers
- **Formatting**: Run `clang-format -i` on modified `.c`/`.h` pantavisor files before committing
- **pvtest todo list**: Update the todo list in `docs/overview/testing/automated-workflow.md` whenever a pvtest is added, modified, or removed — mark it `✓` when complete.
