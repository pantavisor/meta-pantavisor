# Versioning

`meta-pantavisor` uses dynamic versioning tied to its own git repository. This means the `DISTRO_VERSION` variable automatically reflects the latest git tag and commit state of your local `meta-pantavisor` checkout.

## How it works

The version strings for the different distro variants (e.g. `panta-distro`, `panta-appengine`) are defined in `conf/distro/*.conf` using BitBake's `base_get_metadata_git_describe` function:

```bitbake
DISTRO_VERSION = "${@base_get_metadata_git_describe('HEAD', d)}"
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
