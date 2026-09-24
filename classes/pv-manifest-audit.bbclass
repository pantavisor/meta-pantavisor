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
#       ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.manifest.txt
#     with a stable, build-id-free symlink alongside it:
#       ${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.manifest.txt
#   - On any deviation (missing reference or mismatch) a unified-diff patch
#     is written next to the manifest as
#       ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.manifest.patch
#     (also symlinked as ${IMAGE_LINK_NAME}.manifest.patch)
#     and printed in full to the bitbake log via bb.plain (CI-visible).
#     The patch headers use the reference's bare basename, so a maintainer
#     can apply it with:
#       cd <layer>/files && patch < .../${IMAGE_NAME}.manifest.patch

PV_MANIFEST_PREFIX ??= "${PN}"
# DISTRO_CODENAME is optional — many distros leave it unset.
PV_MANIFEST_REFERENCE_NAME ??= "${PV_MANIFEST_PREFIX}_${DISTRO}-${MACHINE}${@'-' + d.getVar('DISTRO_CODENAME') if d.getVar('DISTRO_CODENAME') else ''}.manifest.reference.txt"

# Path prefixes (rootfs-relative, leading slash) whose entire subtree is
# omitted from the manifest. Defaults cover package-manager state files
# whose contents flip on every rebuild without reflecting a real change to
# the image — package add/remove is still detectable via the installed
# files themselves (binaries, libs, configs).
PV_MANIFEST_EXCLUDES ??= "/var/lib/rpm /var/lib/dnf /var/lib/opkg /usr/lib/opkg /var/cache/ldconfig /var/cache/dnf /var/cache/yum"

python pv_manifest_audit() {
    import os, stat, difflib

    rootfs = d.getVar('IMAGE_ROOTFS')
    machine = d.getVar('MACHINE')
    image_name = d.getVar('IMAGE_NAME')
    # Write directly to DEPLOY_DIR_IMAGE rather than IMGDEPLOYDIR so the
    # manifest.txt + manifest.patch survive a bb.fatal in strict mode.
    # IMGDEPLOYDIR is per-recipe staging that bitbake only rsyncs to
    # DEPLOY_DIR_IMAGE on successful task completion — a strict-mode
    # abort in do_rootfs would otherwise leave the diagnostic artifact
    # stranded in WORKDIR where CI never finds it.
    deploy_dir = d.getVar('DEPLOY_DIR_IMAGE')
    workdir = d.getVar('WORKDIR') or ''
    ref_name = d.getVar('PV_MANIFEST_REFERENCE_NAME')
    features = (d.getVar('PANTAVISOR_FEATURES') or '').split()
    strict = 'pv-manifest-strict' in features

    bb.utils.mkdirhier(deploy_dir)
    manifest_path = os.path.join(deploy_dir, image_name + '.manifest.txt')
    patch_path = os.path.join(deploy_dir, image_name + '.manifest.patch')
    ref_path = os.path.join(workdir, ref_name)

    # Stable, build-id-free symlinks pointing at the latest versioned files.
    link_name = d.getVar('IMAGE_LINK_NAME') or ''
    manifest_link = os.path.join(deploy_dir, link_name + '.manifest.txt') if link_name else ''
    patch_link = os.path.join(deploy_dir, link_name + '.manifest.patch') if link_name else ''

    def _relink(link, target):
        if not link:
            return
        try: os.remove(link)
        except OSError: pass
        os.symlink(os.path.basename(target), link)

    def _rmlink(link):
        if not link:
            return
        try: os.remove(link)
        except OSError: pass

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

    _relink(manifest_link, manifest_path)
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
        _rmlink(patch_link)
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
    _relink(patch_link, patch_path)

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
              '# or copy with: cd <layer>/files && cp $TOPDIR/%s' % patch_rel,
              '']
    bb.plain('\n'.join(banner) + patch + '=== end pv-manifest-audit PATCH ===\n')

    advice = (" Manifest: " + manifest_rel + ". Patch: " + patch_rel +
              ". To adopt: ship the regenerated reference via "
              "SRC_URI += \"file://%s\" (or apply the patch under the "
              "layer's files/ directory or copy the new manifest %s)." % (ref_name, manifest_rel))

    if strict:
        bb.fatal(headline + advice +
                 " (PANTAVISOR_FEATURES contains 'pv-manifest-strict')")
    else:
        bb.warn(headline + advice +
                " (advisory — set 'pv-manifest-strict' in "
                "PANTAVISOR_FEATURES to gate the build)")
}

# Run inside do_rootfs, as the last rootfs post-process step, so the audit
# sees the rootfs exactly when it exists. A separate task between do_rootfs
# and do_image cannot be made safe with rm_work: rm_work keeps the do_rootfs
# and do_image stamps but deletes IMAGE_ROOTFS and every other stamp, so such
# a task re-runs on the next build over an empty rootfs, and re-running it
# forces do_image to pack that empty tree (an initramfs of 505 bytes, whose
# kernel panics with "No working init found").
#
# The gate still holds on every build. Being a ROOTFS_POSTPROCESS_COMMAND,
# this function and the variables it reads (PANTAVISOR_FEATURES, so the
# audit/strict mode, PV_MANIFEST_REFERENCE_NAME, PV_MANIFEST_EXCLUDES) are
# part of the do_rootfs signature, and so is the reference file's checksum,
# through SRC_URI. A strict failure fails do_rootfs, which leaves no stamp,
# so the next build re-runs it. A valid do_rootfs stamp, or a do_image_complete
# restored from sstate, therefore always stands for a run in which this same
# audit, in this same mode, against this same reference, passed.
ROOTFS_POSTPROCESS_COMMAND:append = " pv_manifest_audit; "
# image.bbclass turns the command list into do_rootfs vardeps, but the token is
# "pv_manifest_audit;" (the ';' keeps kirkstone's split working) and matches no
# function, so name it explicitly or the mode/reference never reach the hash.
do_rootfs[vardeps] += "pv_manifest_audit"
# IMAGE_NAME carries the build timestamp; keep it out of the signature.
pv_manifest_audit[vardepsexclude] += "DATETIME DATE"
