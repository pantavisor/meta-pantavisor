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
| `docs/overview/` | **Reference for the meta-pantavisor layer itself** — architecture, build system, and build guide as flat `overview/*.md`, with `examples/`, `testing/` (split into `automated/` for the pvtest suite and `manual/` for hand-driven testing plus `manual/testplans/`), and `ci/` as subdirectories |

Rule of thumb: if it is about building or contributing to *this layer*, it goes
in `overview/`; if it is about running Pantavisor on a device, it goes in
`getting-started/`. Ordering within each group is set by `_category_.json` and
`sidebar_position` front matter; `overview/index.md` carries a hand-ordered
topic list, so add new `overview/` pages there too.

Key documents:
- [docs/overview/pantavisor-development.md](docs/overview/pantavisor-development.md) — local source development with workspace overlay
- [docs/overview/get-started.md](docs/overview/get-started.md) — first build guide
- [docs/overview/manifest-audit.md](docs/overview/manifest-audit.md) — rootfs manifest audit (`pv-manifest-audit` / `pv-manifest-strict`)
- [docs/overview/testing/automated/index.md](docs/overview/testing/automated/index.md) — the pvtest harness: architecture, execution models, execution flow, build/install, where output lands
- [docs/overview/testing/automated/appengine.md](docs/overview/testing/automated/appengine.md) — running against the appengine pool, adding/updating tests and containers, the full authoring rules (including cross-target ones), CI
- [docs/overview/testing/automated/device.md](docs/overview/testing/automated/device.md) — real-device runs: manifest, setbootconfig script, tarball substitution, expected non-PASS outcomes
- [docs/overview/testing/automated/pvtest-list.md](docs/overview/testing/automated/pvtest-list.md) — the test list and its status
- [docs/overview/testing/manual/index.md](docs/overview/testing/manual/index.md) — building/loading the appengine image by hand; test plans under `manual/testplans/`
- [docs/overview/ci/tag-sync.md](docs/overview/ci/tag-sync.md) — meta-pantavisor → pantavisor tag-sync workflow and PAT setup
- [docs/overview/ci/changelog.md](docs/overview/ci/changelog.md) — per-release CHANGELOG generator, format, and regen procedure

### Actionability (docs/)

Every feature described in docs/ should give the reader a direct or inline path to do something with it, not just explain the concept. Concretely:

- Alongside (or right after) the conceptual explanation of a feature, show the concrete command, config key, or on-disk path that exercises it — e.g. a `pvcontrol` invocation ([docs/getting-started/develop/cli-tools/pvcontrol.md](docs/getting-started/develop/cli-tools/pvcontrol.md)), a configuration key ([docs/getting-started/develop/cli-tools/configuration.md](docs/getting-started/develop/cli-tools/configuration.md) or [docs/getting-started/develop/application/configure.md](docs/getting-started/develop/application/configure.md)), or a rootfs path to inspect ([docs/overview/manifest-audit.md](docs/overview/manifest-audit.md)).
- Prefer a short fenced code block over prose describing what a command does — show the invocation and, where useful, its output.
- If a feature genuinely has no user-facing action (e.g. it's fully automatic, internal bookkeeping), say so explicitly rather than leaving the reader to wonder — a one-line "this is managed automatically; no action needed" is enough.
- Verify every command, config key, path, and filename you add against the actual source or an existing doc before writing it down — don't invent plausible-looking examples.
- This applies both when writing new docs and when editing existing ones: if you touch a section that only explains a feature without showing how to use it, add the missing hands-on reference while you're there.

### Link conventions (docs/)

- Within the same folder: plain relative links, e.g. `manifest-audit.md#usage`.
- Between `docs/overview/` and `docs/getting-started/`: relative sibling links, e.g. `../../overview/manifest-audit.md`, `../overview/glossary.md#trail`, or `../getting-started/develop/cli-tools/pvcontrol.md`. These resolve both on GitHub and on the published site.
- To pantavisor (core runtime) docs: `../../pantavisor/<section>/<page>.md` (e.g. `../../pantavisor/overview/xconnect.md`, `../../../pantavisor/reference/pantavisor-xconnect.md`) — resolves only on the published site, where both repos' docs are siblings.
- To curated site pages: full URLs, e.g. `https://docs.pantavisor.io/operate/device-access/serial-port`.
- Do not use retired MkDocs-era prefixes — they dangle on the Docusaurus site.
- Syntax: the site renders MDX. Use Docusaurus admonitions (`:::note … :::`), not MkDocs `!!! Note`; avoid MkDocs Material icon codes like `:material-check:`.

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
- **pvtest layout**: the framework spans both repos. The in-container half lives in **pantavisor** under `pvtest/` (`pvtest-run.in`, `utils.in`, `common.in`; built with `PANTAVISOR_PVTEST=ON`, shipped by the `pantavisor-pvtest` package). The host half lives here in `recipes-pv/pantavisor/pantavisor-appengine-distro/` (`test.docker.sh`, `test.native.sh`, `host-common`, `device.txt`, `common`, `tarball-README.md`, `workspace-README.md`, `native-README.md`), and the suites in `recipes-pv/pantavisor-pvtests/files/{local,remote}/`. The deployed tarball layout is unchanged: `local/` and `remote/` sit at the root. Anything context-free that both halves need goes in `common`, which is **duplicated byte-for-byte** across the two repos (container copy from the package, host copy from the tarball) — change one, change the other. Never source `utils` on the host, it shadows `pvcontrol`/`pventer`/`pvcurl`/`pvtx`. `host-common` is the *host-only* half shared by `test.docker.sh` and `test.native.sh` (test selection, tarball install, device manifest, ctrl protocol, summary) — not to be confused with `common`, and not duplicated in pantavisor.
- **pvtest native runner**: `test.native.sh` runs the tester on the host instead of in a container, for real devices only (`--device` required; the appengine pool stays on `test.docker.sh` because its targets *are* containers). It relies on two pantavisor overrides — `PVTEST_LIBDIR` (where `utils`/`common` live) and `PVTEST_ROOT` (prefix stripped to form a test id) — with a user+mount-namespace fallback for runners predating them. The per-target tarball bind mount is replaced by a symlink farm in the workspace, so `-o` still writes goldens back to the source tree. Ships as the slim `pantavisor-pvtest-scripts-<machine>.tar.gz` beside the full distro tarball. Docs: `docs/overview/testing/automated/native.md`.
- **pvtest host config**: a device manifest is per-workstation, not per-workspace — filled copies live in `$PVTEST_CONFIG_DIR/devices/` (default `~/.config/pvtest/devices/`), and `--device` requires a value and resolves it against it, name first: `<value>.txt` there, else `<value>` as a path, else error. **An installed manifest never implies device mode**: a run without `--device` is the appengine pool, whatever is on the host. Only `devices/` is bind-mounted into the tester, so a key named in `exec=` belongs beside the manifest and anything `setbootconfig=`/`setbootconfig_conf=` reads (tokens, board profiles) stays one level up.
- **pvtest division of labour**: `test.docker.sh` is a thin host layer (arg parsing, slot/network/key setup, the flat test queue, one tester launch, one target-lifecycle service, the summary); `pvtest-run` is the sole scheduler for every target. They talk over one ctrl protocol (`PVTEST_CTRL`): request `slot=/cfg=/storage=/rev=/seed=`, response `status=ready|down|failed|unsupported` plus `ae=` and the `exec=`/`host=` that reach it. Two orthogonal variables drive everything — `PVTEST_MODEL` (persistent = keep the target across tests, volatile = one per test) picks the worker body, and `PVTEST_RETYPE` (`container`/`setbootconfig`/`none`) says how a target changes config and whether releasing it destroys it. **A real device is not a separate path**: it is `PVTEST_SLOTS=1` + persistent + `setbootconfig`/`none`. Never re-introduce identity checks ("is this a board?") where a capability check belongs.
- **pvtest todo list**: Update the list in `docs/overview/testing/automated/pvtest-list.md` whenever a pvtest is added, modified, or removed — mark it `✓` when complete.
- **pvtest authoring rules** (full list + canonical skeleton in `docs/overview/testing/automated/appengine.md`): tests share one device/trail and one tester FS, so they must pass both alone and together. Per-test isolation: clone into a unique per-test temp dir (`checkout="$(mktemp -d)/checkout"; cd "$checkout"`) — never a shared path (`/home/checkout`) and never `rm -rf` a shared dir. Do NOT override `$HOME`: the harness exports a per-device Hub-authenticated `$HOME` whose `.pvr/auth.json` is used by `pvr post`/`pvr_post_rev`; clobbering it makes Hub posts fail unauthenticated. Clone the device's current state from the local pvr endpoint (`http://${PVTEST_HOST:-localhost}:12368/cgi-bin/pvr`), not the accumulating Hub trail; guard the clone exit code. After a reboot or `pv_crash`, fence the come-back with `wait_for_down` then `wait_for_target_ready` (SSH -> pv-ctrl -> READY), with a short label (`"after crash 2"`) when a test fences more than once so the stage lines stay distinguishable; inside the readiness fence `_target_ready_log` sends its lines to stderr when no label is set, so they reach test.log and never the diffed stdout — print a test's own diagnostics to stderr for the same reason. Hub revisions: never hardcode — capture with `pvr_post_rev` (in `utils`) and mask the volatile integer in `output`. Determinism: `jq -M`, strip `\r`, mask timestamps/PIDs/hashes/HOME paths; never hand-edit `output` (regenerate with `run … -o`). Clean up created device/user metadata. There is no isolation key: a factory-destructive test (e.g. a GC test that deletes `/storage/trails/0`, or one that fills the disk) must be written to run on a device in any prior state — build its own baseline from posted revisions, derive content-addressed object names dynamically (`sha256sum …`) instead of hard-coding factory hashes, and assert only on paths it creates/removes. `skip:"true"` is local-iteration only — CI/master passes `--fail-on-skip`, which fails the run on any SKIPPED result whatever its reason (`skip` field, `devices` class filter, unmet device config, missing Hub creds).
