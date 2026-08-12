---
title: "Managing Layers with repo"
sidebar_position: 4.5
---
# Managing Layers with `repo`

**Who this is for**: a systems/integration engineer who already manages a
fleet of Yocto layers and products through Google's
[`repo`](https://gerrit.googlesource.com/git-repo/) multi-manifest tool
(`repo init` / `repo sync` against a `manifest.xml`), and wants to add
meta-pantavisor as one more project rather than switching workflows.

This is optional. meta-pantavisor's own CI and the default
[Get Started](get-started.md) guide use a plain `git clone` of
meta-pantavisor, with `kas` fetching `poky`, `meta-openembedded`, and the
rest declaratively per build config. `repo` is not required to build this
layer — it's a way to fold meta-pantavisor into a manifest you already
maintain for other layers/products.

## Why this works: `_source_dir`

Every build config in `kas/build-configs/` sets `_source_dir: .` — meaning
kas resolves all layer checkouts relative to the meta-pantavisor repo root,
not inside `build/`. You can see the exact layout kas expects by dumping any
config:

```bash
kas dump --resolve-refs kas/build-configs/release/docker-x86_64-scarthgap.yaml
```

For the `docker-x86_64-scarthgap` target, this resolves to:

| Repo | Path (relative to meta-pantavisor root) |
|------|------------------------------------------|
| `meta-pantavisor` | `.` |
| `poky` | `layers/poky` |
| `meta-openembedded` | `layers/meta-openembedded` |
| `meta-virtualization` | `layers/meta-virtualization` |

If a `repo sync` already populates exactly these paths, `kas build` finds
the layers in place and updates them in-tree instead of cloning fresh — no
extra kas config needed on top of the normal build-config file.

## A manifest.xml for meta-pantavisor

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="pantavisor" fetch="https://github.com/pantavisor" />
  <remote name="yocto" fetch="https://git.yoctoproject.org" />
  <remote name="oe" fetch="https://github.com/openembedded" />

  <default remote="pantavisor" revision="scarthgap" sync-j="4" />

  <project name="meta-pantavisor" path="." revision="scarthgap" />
  <project name="poky" remote="yocto" path="layers/poky" revision="scarthgap" />
  <project name="meta-openembedded" remote="oe" path="layers/meta-openembedded" revision="scarthgap" />
  <project name="meta-virtualization" remote="yocto" path="layers/meta-virtualization" revision="scarthgap" />
</manifest>
```

`revision` can track a branch (`scarthgap`, as above, matching
`defaults.repos.branch` in `kas/scarthgap.yaml`) or pin an exact commit for
reproducible builds — use the `commit:` values from `kas dump
--resolve-refs` (shown in the table above) if you want the manifest to lock
to the same revisions this layer's own CI builds against.

Host this `manifest.xml` in its own git repo (the usual `repo` convention),
then:

```bash
mkdir my-workspace && cd my-workspace
repo init -u <url-to-your-manifest-repo> -m manifest.xml
repo sync
```

This lays out `meta-pantavisor` at the workspace root and the other layers
under `layers/`, matching the table above exactly.

## Building from the repo-managed checkout

From the workspace root (where `repo sync` placed `meta-pantavisor`):

```bash
./kas-container build kas/build-configs/release/docker-x86_64-scarthgap.yaml
```

No `_source_dir` override is needed — the build config already points kas
at the layers your manifest just synced. Add your own layers (internal
forks, additional BSPs) to the manifest and to a KAS config's `repos:`
block the same way; see [Build System](build-system.md) for how KAS
configuration fragments compose.

## What `repo` does not replace

- `bblayers.conf` composition, `MACHINE`/`DISTRO` selection, and
  multiconfig are still `kas`'s job — `repo` only pins and checks out
  source trees.
- `repo` manages *your* manifest repo's revisions; it doesn't know about
  meta-pantavisor's KAS patches (e.g. the `poky` patches wired up in
  `kas/scarthgap.yaml`) — those still apply through the normal kas build,
  after `repo sync` has placed the source.

## See also

- [Get Started](get-started.md) — the default single-repo path (plain
  `git clone` + kas-fetched layers) if you don't already use `repo`.
- [Build System](build-system.md) — KAS configuration hierarchy and how
  fragments combine.
- [Glossary](glossary.md) — definitions for `kas`, layer, and other terms
  used above.
