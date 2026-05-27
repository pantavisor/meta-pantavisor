# Component Documentation Packaging

meta-pantavisor ships two BitBake classes that together form a documentation
pipeline: one for component recipes to publish their docs, and one for image
recipes to collect and bundle everything.

## Classes

| Class | Inherited by | Produces |
|---|---|---|
| `pantacor-component-docs` | component recipes | `<bpn>-component-docs.tar.zst` in `DEPLOY_DIR_IMAGE` |
| `pantavisor-docs` | image recipes | `<image>.rootfs.docs.tar.zst` in `DEPLOY_DIR_IMAGE` |

---

## pantacor-component-docs — component side

Inherit this class in any recipe that ships documentation. It adds a
`do_create_component_docs` task (after `do_install`, before `do_build`) that
packages the recipe's docs and writes the tarball directly to `DEPLOY_DIR_IMAGE`
so the image class can find it regardless of what the recipe does with
`do_deploy`.

### Variables

| Variable | Default | Description |
|---|---|---|
| `DOCS_SRC_DIR` | `${S}/docs` | Directory to archive recursively |
| `DOCS_FILES` | _(empty)_ | Space-separated list of specific files; takes precedence over `DOCS_SRC_DIR` |
| `DOCS_COMPONENT_NAME` | `${BPN}` | Top-level directory name inside the combined image tarball |

If neither `DOCS_SRC_DIR` exists nor `DOCS_FILES` is set the task emits a
`bbwarn` and skips cleanly — the build does not fail.

### Whole-directory example

The `pantavisor` recipe has a `docs/` subtree inside its source:

```bitbake
inherit cmake gitpkgv pantacor-component-docs
# DOCS_SRC_DIR defaults to ${S}/docs — no override needed
```

### Single-file example

The `pvr` recipe ships only a `README.md` at the source root:

```bitbake
inherit pvgo_mod deploy pantacor-component-docs

DOCS_FILES = "${S}/src/${GO_IMPORT}/README.md"
DOCS_COMPONENT_NAME = "pvr"
```

### Pointing at a non-standard location

```bitbake
inherit pantacor-component-docs

DOCS_SRC_DIR = "${S}/Documentation"
```

---

## pantavisor-docs — image side

Inherit this class in an image recipe to collect component docs and the layer's
own `docs/` directory into a single deployable tarball.

```bitbake
inherit image pvroot-image pantavisor-docs
```

### What it collects

| Source | Destination inside tarball |
|---|---|
| `${META_PANTAVISOR_BASE}/docs/` | `meta-pantavisor/` |
| Every `*-component-docs.tar.zst` in `DEPLOY_DIR_IMAGE` | `<component-name>/` (one dir per component) |

`META_PANTAVISOR_BASE` is set in `conf/layer.conf` to the meta-pantavisor
layer root and is stable even for recipes that live in dynamic layers.

### Variables

| Variable | Default | Description |
|---|---|---|
| `PANTACOR_LAYER_DOCS` | `${META_PANTAVISOR_BASE}/docs` | Layer docs source directory |
| `PANTACOR_LAYER_DOCS_NAME` | `meta-pantavisor` | Top-level name in the tarball |

### Output

Three files are written to `DEPLOY_DIR_IMAGE`:

```
<IMAGE_LINK_NAME>.rootfs-<timestamp>.rootfs.docs.tar.zst   ← actual file
<IMAGE_LINK_NAME>.docs.tar.zst                              ← "latest" symlink
<IMAGE_LINK_NAME>.<git-hash>[+<tag>].docs.tar.zst           ← versioned symlink
```

The versioned symlink embeds the short git hash of the meta-pantavisor layer
(and the git tag if the current commit is tagged), making it easy to trace
which layer revision produced the docs.

### Tarball layout

```
meta-pantavisor/
  ci/
  how-to-build/
  ...
pantavisor/
  <upstream pantavisor docs>
pvr/
  README.md
```

---

## Running standalone

To generate only the docs tarball without a full image build:

```sh
bitbake -c create_pantacor_docs <image-recipe>
# e.g.
bitbake -c create_pantacor_docs pantavisor-appengine
```

Because `do_create_pantacor_docs` uses
`[recrdeptask] += "do_create_component_docs"`, BitBake automatically builds
all packages in the image's dependency tree up to `do_install` and runs their
`do_create_component_docs` tasks — no rootfs assembly or image creation is
needed.

To force regeneration after a class or docs change:

```sh
bitbake -f -c create_pantacor_docs <image-recipe>
```

---

## Adding a new component

1. Inherit the class and set the doc source:

   ```bitbake
   inherit pantacor-component-docs

   # option A — whole directory (default: ${S}/docs)
   DOCS_SRC_DIR = "${S}/docs"

   # option B — specific files
   DOCS_FILES = "${S}/README.md ${S}/CHANGELOG.md"

   # optional — override the directory name in the combined tarball
   DOCS_COMPONENT_NAME = "my-component"
   ```

2. Rebuild the image docs tarball:

   ```sh
   bitbake -f -c create_pantacor_docs <image-recipe>
   ```

No changes to the image recipe are needed — the image class discovers all
`*-component-docs.tar.zst` files automatically.
