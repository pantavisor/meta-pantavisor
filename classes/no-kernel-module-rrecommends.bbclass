# Drop kernel-module-* from every package's RRECOMMENDS.
#
# Only the board kernel recipe provides kernel-module-*, and image do_rootfs
# follows RRECOMMENDS across whole recipes, so one such recommend in a common
# recipe (util-linux via bash/shadow, cryptsetup, iptables) makes every
# container image wait on the board kernel's fetch and build. Pantavisor never
# installs modules as packages: they ship in the BSP's modules.squashfs.

python () {
    for pkg in (d.getVar('PACKAGES') or '').split():
        recs = bb.utils.explode_deps(d.getVar('RRECOMMENDS:' + pkg) or '')
        mods = [r for r in recs if r.startswith('kernel-module-')]
        if mods:
            # setVar, not appendVar: only setVar parses the :remove operator.
            d.setVar('RRECOMMENDS:%s:remove' % pkg, ' '.join(mods))
}
