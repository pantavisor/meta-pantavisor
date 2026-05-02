# pv-manifest-audit.bbclass
#
# Generates a deterministic manifest of the rootfs (path, mode, uid, gid,
# type, size, symlink target) and audits it against a reference file
# fetched into ${WORKDIR}.
#
# Activation: this class is meant to be inherited conditionally on
# PANTAVISOR_FEATURES, e.g. in the recipe:
#
#   inherit ${@bb.utils.contains_any('PANTAVISOR_FEATURES', \
#       'pv-manifest-audit pv-manifest-strict', 'pv-manifest-audit', '', d)}
#
# Modes:
#   - 'pv-manifest-audit'  → advisory: deviations emit the patch as a WARNING
#                            (build proceeds). Use this in dev distros.
#   - 'pv-manifest-strict' → enforcing: deviations are FATAL (build fails).
#                            Use this in release/CI distros to gate drift.
#                            'strict' implies 'audit'; if both are set,
#                            'strict' wins.
#
# Reference filename (in WORKDIR):
#     ${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}-${DISTRO_CODENAME}.manifest.reference.txt
#
# PV_MANIFEST_PREFIX defaults to ${PN}; recipes should pin it to a stable
# image label (e.g. "pv-initramfs", "pv-appengine") so the reference name
# is decoupled from package versioning.
#
# The class itself does NOT touch SRC_URI. To enable the audit, a layer
# (this one for upstream-supported machines, or a downstream bbappend for
# their own MACHINE) adds:
#
#     FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
#     SRC_URI += "file://${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}-${DISTRO_CODENAME}.manifest.reference.txt"
#
# and ships the file under their layer's files/. Override semantics are the
# stock Yocto ones — FILESEXTRAPATHS:prepend in a bbappend wins over the
# upstream layer's copy.
#
# Output:
#   - Manifest is always written to
#       ${IMGDEPLOYDIR}/${IMAGE_NAME}.manifest.txt
#   - On any deviation (missing reference or mismatch) a unified-diff patch
#     is written next to the manifest as
#       ${IMGDEPLOYDIR}/${IMAGE_NAME}.manifest.patch
#     and printed in full to the bitbake log via bb.plain (CI-visible).
#     The patch headers use the reference's bare basename, so a maintainer
#     can apply it with:
#       cd <layer>/files && patch < .../${IMAGE_NAME}.manifest.patch

PV_MANIFEST_PREFIX ??= "${PN}"
PV_MANIFEST_REFERENCE_NAME ??= "${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}-${DISTRO_CODENAME}.manifest.reference.txt"

# Path prefixes (rootfs-relative, leading slash) whose entire subtree is
# omitted from the manifest. Defaults cover package-manager state files
# whose contents flip on every rebuild without reflecting a real change to
# the image — package add/remove is still detectable via the installed
# files themselves (binaries, libs, configs).
PV_MANIFEST_EXCLUDES ??= "/var/lib/rpm /var/lib/dnf /var/lib/opkg /usr/lib/opkg /var/cache/ldconfig /var/cache/dnf /var/cache/yum"

python pv_manifest_audit_run() {
    import os, stat, difflib

    rootfs = d.getVar('IMAGE_ROOTFS')
    machine = d.getVar('MACHINE')
    image_name = d.getVar('IMAGE_NAME')
    deploy_dir = d.getVar('IMGDEPLOYDIR') or d.getVar('DEPLOY_DIR_IMAGE')
    workdir = d.getVar('WORKDIR') or ''
    ref_name = d.getVar('PV_MANIFEST_REFERENCE_NAME')
    features = (d.getVar('PANTAVISOR_FEATURES') or '').split()
    strict = 'pv-manifest-strict' in features

    bb.utils.mkdirhier(deploy_dir)
    manifest_path = os.path.join(deploy_dir, image_name + '.manifest.txt')
    patch_path = os.path.join(deploy_dir, image_name + '.manifest.patch')
    ref_path = os.path.join(workdir, ref_name)

    # Render paths relative to TOPDIR so the strings are usable both inside
    # the kas/bitbake container and on the host (TOPDIR maps to build/).
    topdir = d.getVar('TOPDIR') or ''
    def _rel(p):
        try:
            return os.path.relpath(p, topdir)
        except ValueError:
            return p
    manifest_rel = _rel(manifest_path)
    patch_rel = _rel(patch_path)

    rootfs = os.path.realpath(rootfs)

    excludes = [p for p in (d.getVar('PV_MANIFEST_EXCLUDES') or '').split() if p]
    def _excluded(rel):
        for ex in excludes:
            if rel == ex or rel.startswith(ex + '/'):
                return True
        return False

    entries = []
    for dirpath, dirnames, filenames in os.walk(rootfs, followlinks=False):
        # Prune excluded subtrees so we don't descend into them at all.
        pruned = []
        for dn in list(dirnames):
            sub_rel = '/' + os.path.relpath(os.path.join(dirpath, dn), rootfs)
            if _excluded(sub_rel):
                pruned.append(dn)
        for dn in pruned:
            dirnames.remove(dn)
        dirnames.sort()
        names = sorted(set(dirnames) | set(filenames))
        for name in names:
            full = os.path.join(dirpath, name)
            try:
                st = os.lstat(full)
            except OSError:
                continue
            rel = '/' + os.path.relpath(full, rootfs)
            if rel == '/.':
                continue
            if _excluded(rel):
                continue
            mode = stat.S_IMODE(st.st_mode)
            if stat.S_ISLNK(st.st_mode):
                ftype = 'l'
                try:
                    target = os.readlink(full)
                except OSError:
                    target = ''
                tail = ' -> ' + target
            elif stat.S_ISDIR(st.st_mode):
                ftype, tail = 'd', ''
            elif stat.S_ISREG(st.st_mode):
                ftype, tail = 'f', ''
            elif stat.S_ISCHR(st.st_mode):
                ftype = 'c'
                tail = ' %d,%d' % (os.major(st.st_rdev), os.minor(st.st_rdev))
            elif stat.S_ISBLK(st.st_mode):
                ftype = 'b'
                tail = ' %d,%d' % (os.major(st.st_rdev), os.minor(st.st_rdev))
            elif stat.S_ISFIFO(st.st_mode):
                ftype, tail = 'p', ''
            elif stat.S_ISSOCK(st.st_mode):
                ftype, tail = 's', ''
            else:
                ftype, tail = '?', ''
            entries.append((rel, '%s %04o %d %d %s%s' % (
                ftype, mode, st.st_uid, st.st_gid, rel, tail)))

    entries.sort(key=lambda e: e[0])
    body = '\n'.join(line for _, line in entries) + '\n'

    with open(manifest_path, 'w') as f:
        f.write('# pv-manifest-audit v1\n')
        f.write('# format: type mode uid gid path[ -> symlink-target | major,minor]\n')
        f.write('# machine: %s\n' % machine)
        f.write('# distro:  %s (%s)\n' % (d.getVar('DISTRO') or '', d.getVar('DISTRO_CODENAME') or ''))
        f.write('# prefix:  %s\n' % (d.getVar('PV_MANIFEST_PREFIX') or ''))
        if excludes:
            f.write('# exclude: %s\n' % ' '.join(excludes))
        f.write(body)

    bb.note('pv-manifest-audit: wrote %s (%d entries)' % (manifest_rel, len(entries)))

    have_ref = os.path.exists(ref_path)
    ref_text = ''
    if have_ref:
        with open(ref_path, 'r') as f:
            ref_text = f.read()
    with open(manifest_path, 'r') as f:
        cur_text = f.read()

    if have_ref and ref_text == cur_text:
        bb.note('pv-manifest-audit: rootfs matches reference (%s)' % ref_name)
        if os.path.exists(patch_path):
            try: os.unlink(patch_path)
            except OSError: pass
        return

    # Build a patch whose headers carry the bare basename so it applies
    # from inside the layer's files/ directory:
    #     cd <layer>/files && patch < .../${IMAGE_NAME}.manifest.patch
    patch = ''.join(difflib.unified_diff(
        ref_text.splitlines(keepends=True),
        cur_text.splitlines(keepends=True),
        fromfile=ref_name,
        tofile=ref_name))
    with open(patch_path, 'w') as f:
        f.write(patch)

    if have_ref:
        headline = ("pv-manifest-audit: rootfs manifest for MACHINE '%s' "
                    "differs from reference '%s'." % (machine, ref_name))
    else:
        headline = ("pv-manifest-audit: no reference manifest '%s' shipped "
                    "via SRC_URI for MACHINE '%s' — emitting full-add patch."
                    % (ref_name, machine))

    banner = ['',
              '=== pv-manifest-audit PATCH (%s, %s) ===' % (
                  machine, 'STRICT' if strict else 'audit'),
              '# patch file: %s (relative to TOPDIR)' % patch_rel,
              '# manifest:   %s (relative to TOPDIR)' % manifest_rel,
              '# apply with: cd <layer>/files && patch < $TOPDIR/%s' % patch_rel,
              '']
    bb.plain('\n'.join(banner) + patch + '=== end pv-manifest-audit PATCH ===\n')

    advice = (" Patch: " + patch_rel +
              ". To adopt: ship the regenerated reference via "
              "SRC_URI += \"file://%s\" (or apply the patch under the "
              "layer's files/ directory)." % ref_name)

    if strict:
        bb.fatal(headline + advice +
                 " (PANTAVISOR_FEATURES contains 'pv-manifest-strict')")
    else:
        bb.warn(headline + advice +
                " (advisory — set 'pv-manifest-strict' in "
                "PANTAVISOR_FEATURES to gate the build)")
}

ROOTFS_POSTPROCESS_COMMAND += "pv_manifest_audit_run;"

# Make the audit re-run when feature flags or naming inputs change.
pv_manifest_audit_run[vardeps] += "PANTAVISOR_FEATURES PV_MANIFEST_PREFIX PV_MANIFEST_REFERENCE_NAME PV_MANIFEST_EXCLUDES"
