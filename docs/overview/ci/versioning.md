---
sidebar_position: 5
---
# Versioning

`meta-pantavisor` uses dynamic versioning tied to its own git repository. This means the `DISTRO_VERSION` variable automatically reflects the latest git tag and commit state of your local `meta-pantavisor` checkout.

## How it works

The version strings for the different distro variants (e.g. `panta-distro`, `panta-appengine`) are defined in `conf/distro/*.conf` using OpenEmbedded's `get_metadata_git_describe` helper:

```bitbake
DISTRO_VERSION = "${@oe.buildcfg.get_metadata_git_describe(os.path.dirname(os.path.dirname(d.getVar('FILE'))))}"
```

During the parsing phase of a build, Yocto executes a `git describe` command against the `meta-pantavisor` repository.

*   **If you build exactly on a tag:** Bitbake sets `DISTRO_VERSION` to the tag name (e.g., `028-rc10`).
*   **If you have commits on top of a tag:** Bitbake appends the commit count and short hash dynamically (e.g., `028-rc10-4-gabcdef`).

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
