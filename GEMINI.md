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

## Documentation Structure

New documents should follow this layout:

| Directory | Content type |
|-----------|-------------|
| `docs/getting-started/` | **Using Pantavisor**, independent of this layer — install/flash guides (`how-to-install/`, incl. `boards/`), app development (`develop/`), device operation (`operate/`), plus `start/`, `migrate/`, `security/`, `benchmarks/`, `solutions/`, `troubleshooting/`, `licensing/`, `community/` |
| `docs/overview/` | **Reference for the meta-pantavisor layer itself** — architecture, build system, and build guide as flat `overview/*.md`, with `examples/`, `testing/` (split into `automated/` for the pvtest suite and `manual/` for hand-driven testing plus `manual/testplans/`), and `ci/` as subdirectories |

Rule of thumb: if it is about building or contributing to *this layer*, it goes
in `overview/`; if it is about running Pantavisor on a device, it goes in
`getting-started/`. Ordering within each group is set by `_category_.json` and
`sidebar_position` front matter; `overview/index.md` carries a hand-ordered
topic list, so add new `overview/` pages there too.

Key documents:
- [docs/overview/pantavisor-development.md](docs/overview/pantavisor-development.md) — local source development with workspace overlay
- [docs/overview/get-started.md](docs/overview/get-started.md) — first build guide
- [docs/overview/testing/automated/index.md](docs/overview/testing/automated/index.md) — the pvtest harness: architecture, assignment models, execution flow, `test.docker.sh` flags
- [docs/overview/testing/automated/appengine.md](docs/overview/testing/automated/appengine.md) — running against the appengine pool, authoring/updating tests, CI
- [docs/overview/testing/automated/devices.md](docs/overview/testing/automated/devices.md) — real-device runs: manifest, re-type hook, tarball substitution
- [docs/overview/testing/automated/pvtest-list.md](docs/overview/testing/automated/pvtest-list.md) — the test list and its status
- [docs/overview/testing/manual/index.md](docs/overview/testing/manual/index.md) — building/loading the appengine image by hand; test plans under `manual/testplans/`

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
- **pvtest layout**: the whole framework lives in `recipes-pv/pantavisor-pvtests/`, split by role — `files/pvtest/` (the in-container runner `pvtest-run`, its `utils` library, and `common`, shared with the host), `files/host/` (`test.docker.sh`, `devices.txt`, `README.md`), `files/data/{local,remote}/` (the suites). The deployed tarball layout is unchanged: `local/` and `remote/` sit at the root. Anything context-free that both halves need goes in `files/pvtest/common`; never source `utils` on the host, it shadows `pvcontrol`/`pventer`/`pvcurl`/`pvtx`.
- **pvtest container tarballs are per target, the suites are not**: only the tarballs vary by target (architecture + signing CA), so `local/` and `remote/` stay single shared trees and each target's containers live in `targets/<type>/<scope>/`. `test.docker.sh` bind-mounts `targets/<type>/<scope>/` over `/work/<scope>/common/tarballs` at tester start, so the tester always sees the same path and **no test data mentions a target** — every `test.json`'s `../../common/tarballs/<name>.pvrexport.tgz` and the absolute `/work/local/common/tarballs/...` references in test scripts stay target-agnostic. `<type>` is the `devices.txt` `type=` field, `appengine` without `--devices`, `PVTEST_DEVICE_TYPE` overrides both; a missing target tree aborts the run before any container starts. Install with `install-tarballs -t <type>` (creates the tree; each target keeps its own manifest). Tests reference containers by Yocto deploy name — the `.pvrexport.tgz` suffix comes from `container-pvrexport.bbclass` and is identical for every MACHINE, so a board build's `deploy/images/<machine>/` is a drop-in source with no renaming. `PV_PVTEST_CONTAINERS` in `pantavisor-appengine-distro.bb` is the single list driving both `do_create_tarball[depends]` and the staging loop; `PV_PVTEST_CONTAINERS_XCONNECT` is the subset built only when `PANTAVISOR_FEATURES` carries `xconnect-dbus-systembus`, whose tests must be pinned `"devices": ["appengine"]`.
- **pvtest todo list**: Update the list in `docs/overview/testing/automated/pvtest-list.md` whenever a pvtest is added, modified, or removed — mark it `✓` when complete.
- **pvtest authoring rules** (full list + canonical skeleton in `docs/overview/testing/automated/appengine.md`): tests share one device/trail and one tester FS, so they must pass both alone and together. Per-test isolation: clone into a unique per-test temp dir (`checkout="$(mktemp -d)/checkout"; cd "$checkout"`) — never a shared path (`/home/checkout`) and never `rm -rf` a shared dir. Do NOT override `$HOME`: the harness exports a per-device Hub-authenticated `$HOME` whose `.pvr/auth.json` is used by `pvr post`/`pvr_post_rev`; clobbering it makes Hub posts fail unauthenticated. Clone the device's current state from the local pvr endpoint (`http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr`), not the accumulating Hub trail; guard the clone exit code. After a reboot or `crash_pv`, fence the come-back with `wait_for_down` then `wait_for_target_ready` (SSH -> pv-ctrl -> READY), with a short label (`"after crash 2"`) when a test fences more than once so the stage lines stay distinguishable; inside the readiness fence `_target_ready_log` sends its lines to stderr when no label is set, so they reach test.log and never the diffed stdout — print a test's own diagnostics to stderr for the same reason. Hub revisions: never hardcode — capture with `pvr_post_rev` (in `utils`) and mask the volatile integer in `output`. Determinism: `jq -M`, strip `\r`, mask timestamps/PIDs/hashes/HOME paths; never hand-edit `output` (regenerate with `run … -o`). Clean up created device/user metadata. There is no isolation key: a factory-destructive test (e.g. a GC test that deletes `/storage/trails/0`, or one that fills the disk) must be written to run on a device in any prior state — build its own baseline from posted revisions, derive content-addressed object names dynamically (`sha256sum …`) instead of hard-coding factory hashes, and assert only on paths it creates/removes. `skip:"true"` is local-iteration only — CI/master passes `--fail-on-skip`, which fails the run on any SKIPPED result whatever its reason (`skip` field, `devices` class filter, unmet device config, missing Hub creds).
