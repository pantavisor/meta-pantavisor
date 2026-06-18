# meta-pantavisor

Yocto/OpenEmbedded layer for building Pantavisor-based BSP images for embedded Linux systems. Provides recipes, BitBake classes, and KAS configurations for building complete initramfs + container images.

## Key Components

| Component | Description |
|-----------|-------------|
| `kas/` | KAS configuration fragments (machines, platforms, Yocto releases, workspace overlay) |
| `recipes-pv/pantavisor/` | Core Pantavisor runtime recipe |
| `recipes-pv/images/` | BSP, initramfs, appengine image recipes |
| `recipes-containers/pv-examples/` | Example containers for xconnect service mesh testing (incl. `pv-example-svc-tcp-{provider,consumer}` for the service-IP layer) |
| `worktree-create.sh` / `worktree-remove.sh` | **Always use these for new branch worktrees** — they share `build/sstate-cache` + `build/downloads` with the main checkout. Plain `git worktree add` skips cache sharing and forces fresh sstate rebuilds. Idempotent. |
| `classes/pvbase.bbclass` | Defines `PANTAVISOR_FEATURES` variable and defaults |
| `classes/container-pvrexport.bbclass` | Container pvrexport packaging |
| `.github/machines.json` | CI machine configurations — edit before regenerating workflows |
| `CHANGELOG/` | Per-major-version release notes (`CHANGELOG-NNN.md`); generated from tag pushes |


## Documentation Structure

New documents should follow this layout:

| Directory | Content type |
|-----------|-------------|
| `docs/overview/` | Architecture, design, layer overview |
| `docs/how-to-build/` | Build recipes, workspace dev, container authoring |
| `docs/how-to-install/` | Board-specific flashing guides |
| `docs/examples/` | xconnect and other feature examples |
| `docs/testing/` | Development and automated test workflows; test plans under `testplans/` |
| `docs/ci/` | CI/release automation — workflow design, tag sync, secrets setup |

Key documents:
- [docs/how-to-build/pantavisor-development.md](docs/how-to-build/pantavisor-development.md) — local source development with workspace overlay (**the only sane way** to iterate on Pantavisor source — do NOT create a separate Pantavisor git worktree, devtool manages `build/workspace/sources/pantavisor` and external checkouts aren't reachable from inside `kas-container`)
- [docs/how-to-build/get-started.md](docs/how-to-build/get-started.md) — first build guide (includes the `worktree-create.sh` parallel-branch workflow)
- [docs/overview/xconnect-services.md](docs/overview/xconnect-services.md) — service-IP layer (ClusterIPs, `<service>.pv.local`, k8s-Services-style mediation)
- [docs/how-to-build/xconnect-services.md](docs/how-to-build/xconnect-services.md) — adding a TCP service to a container
- [docs/testing/testplans/testplan-xconnect-services.md](docs/testing/testplans/testplan-xconnect-services.md) — service-IP test plan
- [docs/how-to-build/manifest-audit.md](docs/how-to-build/manifest-audit.md) — rootfs manifest audit (`pv-manifest-audit` / `pv-manifest-strict`)
- [docs/testing/development-workflow.md](docs/testing/development-workflow.md) — manual appengine testing during development
- [docs/testing/automated-workflow.md](docs/testing/automated-workflow.md) — structured testing with test.docker.sh (valgrind, CI, todo list)
- [docs/ci/tag-sync.md](docs/ci/tag-sync.md) — meta-pantavisor → pantavisor tag-sync workflow and PAT setup
- [docs/ci/changelog.md](docs/ci/changelog.md) — per-release CHANGELOG generator, format, and regen procedure

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

- **Pull requests**: Always open as drafts (`gh pr create --draft`); promote to ready only when CI passes and the branch is review-ready.
- **Commits**: Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) v1.0.0
- **Kconfig changes**: Run `.github/scripts/makemachines` after modifying Kconfig
- **Storage state**: Use fresh storage volumes when testing pvtx.d changes (`docker volume rm storage-test`)
- **API testing**: Use `pvcurl`/`pvcontrol` (not `curl`) inside appengine containers
- **Formatting**: Run `clang-format -i` on modified `.c`/`.h` pantavisor files before committing
- **pvtest todo list**: Update the todo list in `docs/testing/automated-workflow.md` whenever a pvtest is added, modified, or removed — mark it `✓` when complete.
