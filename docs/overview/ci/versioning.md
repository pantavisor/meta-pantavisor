---
sidebar_position: 5
---
# Versioning

`meta-pantavisor` uses dynamic versioning tied to its own git repository. This means the `DISTRO_VERSION` variable automatically reflects the latest git tag and commit state of your local `meta-pantavisor` checkout.

## How it works

All four distros (`panta-distro`, `panta-distro-bsp`, `panta-distro-app`,
`panta-appengine`) take `DISTRO_VERSION` from one include,
`conf/distro/panta-version.inc`, which runs `git describe` on this layer:

```bitbake
DISTRO_VERSION = "${@bb.process.run(['git', 'describe', '--tags', '--match', '[0-9][0-9][0-9]*', '--always', '--dirty'], cwd=d.getVar('META_PANTAVISOR_BASE'))[0].strip()}"
DISTRO_VERSION[vardepvalue] = "${DISTRO_VERSION}"
```

*   **If you build exactly on a tag:** `DISTRO_VERSION` is the tag name (e.g. `031-rc7`).
*   **If you have commits on top of a tag:** the commit count and short hash are appended (e.g. `031-rc7-4-gabcdef12`).
*   **If tracked files are modified:** `-dirty` is appended.
*   **If no tag is reachable** (a shallow CI checkout of an untagged commit): it is the short hash.

`--tags` matters: RC tags are lightweight, and without it `git describe` skips
them and reports the last annotated tag (a build past `031-rc7` would say
`030-rc3-…`). `[vardepvalue]` makes task signatures hash the resulting string
rather than the expression, so any change of version rebuilds pantavisor,
`os-release`, `base-files` and the images instead of reusing sstate stamped
with the previous version.

This ensures the `DISTRO_VERSION` passed into the `pantavisor` runtime accurately tracks the Yocto layer's state without requiring manual edits to the configuration files.

## Releasing a new version

For day-to-day development, no manual version steps are required. 

When you are ready to cut a new release or align the layer with a new upstream `pantavisor` base version, use the `scripts/set-version.sh` tool to create the base tag:

```bash
./scripts/set-version.sh 028-rc10
```

This creates a local git tag. All subsequent builds will automatically anchor to this new tag for their `DISTRO_VERSION`.

## Cutting a stable release

`DISTRO_VERSION` is not just metadata — it is compiled into the pantavisor
binary at build time:

```bitbake
# recipes-pv/pantavisor/pantavisor_git.bb
EXTRA_OECMAKE += '-DPANTAVISOR_DISTRO_VERSION="${DISTRO_VERSION}"'
```

`recipes-pv/pantavisor/pantavisor-appengine-distro.bb` also folds it into
`BUILD_SUFFIX`. Two consequences for a stable release:

- **A stable release is rebuilt, never re-published from the RC's artifacts.**
  Copying `030-rc3`'s images to `030/` URLs would leave them reporting
  `030-rc3` internally, because the string was baked in when they were built.
  The rebuild is warm, not cold: only pantavisor, `os-release` and the
  downstream rootfs / wic / pvrexport / SDK assembly get new signatures —
  everything else comes from the sstate the RC already populated.
- **The stable tag must be annotated, and must sit on its own commit.** The
  [stable flow](changelog.md#stable-flow) puts the CHANGELOG-only finalize
  commit on top of the chosen RC and tags that, so `git describe` resolves
  unambiguously:

  ```sh
  git switch -c release/030 030-rc3
  ./.github/scripts/make-changelog.sh --finalize 030
  git tag -a 030 -m "Release 030"
  git describe            # 030
  ```

  Two tags on one commit fall back to a tie-break: a *lightweight* `030`
  alongside the annotated `030-rc3` loses it, and the build would be stamped
  `030-rc3`.

To check what a build will stamp, ask bitbake; to check what a running device
reports, ask [`pvcontrol`](../../getting-started/develop/cli-tools/pvcontrol.md):

```sh
# on the build host
kas shell kas/build-configs/release/rpi-scarthgap.yaml \
  -c 'bitbake -e pantavisor-starter' | grep '^DISTRO_VERSION='

# on the device — build and current revision info
pvcontrol buildinfo
```
