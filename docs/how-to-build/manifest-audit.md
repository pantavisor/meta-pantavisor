---
sidebar_position: 5
---
# Pantavisor Manifest Audit

`pv-manifest-audit.bbclass` produces a deterministic listing of every entry in
an image rootfs (path, type, mode, ownership, symlink targets, device nodes)
and compares it against a reference checked into a layer. Drift is surfaced as
a unified-diff patch — printed to the bitbake log, written to the deploy
directory, and (in strict mode) used to fail the build.

This catches a class of regressions that ordinary CI does not:

- a package starts shipping a setuid binary it never had before,
- a recipe accidentally drops a previously-installed file,
- ownership flips from `root:root` to `messagebus:messagebus`,
- a new symlink is introduced in `/etc`,
- a postinst leaves stray files in `/var`.

None of these break the build. All of them change device behaviour in the
field.

## Two modes

The class is inherited only when one of the feature flags is set in
`PANTAVISOR_FEATURES`:

| Flag                  | Behaviour on drift              | Use in                           |
|-----------------------|---------------------------------|----------------------------------|
| `pv-manifest-audit`   | Patch + WARNING (build proceeds)| Dev distros, default in `panta`  |
| `pv-manifest-strict`  | Patch + ERROR  (build fails)    | Release / CI distros             |

`pv-manifest-strict` implies `pv-manifest-audit`. Setting both is fine — strict
wins.

The default `panta` and `panta-appengine` distros enable advisory mode out of
the box; flip to strict in a release config:

```bitbake
PANTAVISOR_FEATURES:append = " pv-manifest-strict"
```

## Reference filename

References live in a layer's `files/` directory and are pulled into
`${WORKDIR}` via `SRC_URI`:

```
${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}-${DISTRO_CODENAME}.manifest.reference.txt
```

`PV_MANIFEST_PREFIX` is set per recipe (`pv-initramfs` for the initramfs image,
`pv-appengine` for the appengine image). Concrete examples:

```
pv-initramfs_panta-raspberrypi-scarthgap.manifest.reference.txt
pv-initramfs_panta-raspberrypi5-scarthgap.manifest.reference.txt
pv-appengine_panta-appengine-raspberrypi-scarthgap.manifest.reference.txt
```

The underscore separates the recipe prefix from the distro/machine/codename
triple — both halves can themselves contain dashes, so the underscore makes
the boundary unambiguous.

## How to add a reference for a new MACHINE / DISTRO

The reference is a normal `SRC_URI` `file://` entry. Add it from this layer
(for upstream-supported machines) or from a downstream `.bbappend`:

```bitbake
# pantavisor-initramfs.bbappend in your layer
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://pv-initramfs_panta-<MACHINE>-<CODENAME>.manifest.reference.txt"
```

Drop the file under `<your-layer>/files/`. Normal Yocto override semantics
apply: `FILESEXTRAPATHS:prepend` in a bbappend wins over the upstream layer's
copy.

Bootstrapping a brand-new MACHINE:

1. Build with advisory mode (`pv-manifest-audit` set, no `pv-manifest-strict`).
2. The build prints a full-add patch to the bitbake log and writes
   `${IMGDEPLOYDIR}/${IMAGE_NAME}.manifest.patch` (also copied to the final
   `deploy/images/<MACHINE>/` directory).
3. Apply the patch under your layer's `files/` directory:

   ```sh
   cd <layer>/files
   patch < <build>/tmp-scarthgap/.../pantavisor-initramfs-<MACHINE>-<TS>.manifest.patch
   ```

4. Add the matching `SRC_URI += "file://..."` line and rebuild. The next
   `do_rootfs` should match cleanly.

## Output artifacts

Two files land in the image deploy dir for every build:

| File                              | When written                          |
|-----------------------------------|---------------------------------------|
| `${IMAGE_NAME}.manifest.txt`      | Always                                |
| `${IMAGE_NAME}.manifest.patch`    | Only when there is a drift to record  |

The patch is also dumped in full into the bitbake log via `bb.plain` so it
shows in CI output without any extra plumbing. Look for the banner:

```
=== pv-manifest-audit PATCH (<MACHINE>, audit|STRICT) ===
# patch file: tmp-<codename>/.../...manifest.patch (relative to TOPDIR)
# manifest:   tmp-<codename>/.../...manifest.txt (relative to TOPDIR)
# apply with: cd <layer>/files && patch < $TOPDIR/<patch>
--- <reference name>
+++ <reference name>
...
=== end pv-manifest-audit PATCH ===
```

## Manifest format

```
# pv-manifest-audit v1
# format: type mode uid gid path[ -> symlink-target | major,minor]
# machine: <MACHINE>
# distro:  <DISTRO> (<DISTRO_CODENAME>)
# prefix:  <PV_MANIFEST_PREFIX>
# exclude: <space-separated paths excluded from the walk>
<entries, sorted by path>
```

Each entry is `<type> <mode> <uid> <gid> <path>[<tail>]` where `tail` is
` -> <target>` for a symlink, ` <major>,<minor>` for a device node, or empty.
Types: `f` regular, `d` directory, `l` symlink, `c` char device, `b` block
device, `p` fifo, `s` socket.

File **size is intentionally omitted**: it would diff on every dependency
version bump (busybox, mbedtls, kernel modules) without reflecting a
meaningful behavioural change. Adding or removing a file is still detected via
its presence or absence.

## Excludes

`PV_MANIFEST_EXCLUDES` is a space-separated list of rootfs-relative path
prefixes to skip. Defaults cover package-manager state files whose contents
flip on every rebuild without indicating real change:

```
/var/lib/rpm
/var/lib/dnf
/var/lib/opkg
/usr/lib/opkg
/var/cache/ldconfig
/var/cache/dnf
/var/cache/yum
```

Package add/remove is still detectable via the actual installed files
(binaries, libs, configs in `/usr`, `/etc`, etc.); only the package-manager
bookkeeping is filtered.

A recipe or downstream layer can extend the list:

```bitbake
PV_MANIFEST_EXCLUDES:append = " /etc/ssh/ssh_host_keys /etc/machine-id"
```

The exclude list is part of the task's input hash (vardeps), so changes
trigger a `do_rootfs` rerun.

## Class variables

| Variable                        | Default                                                                   | Purpose                                                                  |
|---------------------------------|---------------------------------------------------------------------------|--------------------------------------------------------------------------|
| `PV_MANIFEST_PREFIX`            | `${PN}`                                                                   | Recipe-stable label embedded in the reference filename                   |
| `PV_MANIFEST_REFERENCE_NAME`    | `${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}-${DISTRO_CODENAME}.manifest.reference.txt` | Basename of the reference fetched into `${WORKDIR}`         |
| `PV_MANIFEST_EXCLUDES`          | (see above)                                                               | Rootfs-relative path prefixes to omit from the manifest                  |

## Inheriting the class

Recipes inherit the class conditionally so it is a no-op when neither feature
flag is set:

```bitbake
inherit ${@bb.utils.contains_any('PANTAVISOR_FEATURES', \
    'pv-manifest-audit pv-manifest-strict', 'pv-manifest-audit', '', d)}
PV_MANIFEST_PREFIX = "pv-initramfs"   # or pv-appengine, etc.
```

Currently inherited by:

- `recipes-pv/images/pantavisor-initramfs.bb`
- `dynamic-layers/virtualization-layer/recipes-pv/images/pantavisor-appengine.inc`

## Implementation

`classes/pv-manifest-audit.bbclass` registers a `ROOTFS_POSTPROCESS_COMMAND`
(`pv_manifest_audit_run`). It runs under pseudo, so the uid/gid recorded in
the manifest are the same ones that end up in the cpio / tarball. The task is
re-invalidated when `PANTAVISOR_FEATURES`, `PV_MANIFEST_PREFIX`,
`PV_MANIFEST_REFERENCE_NAME`, or `PV_MANIFEST_EXCLUDES` change (declared via
`vardeps`).
