# Replace meta-sunxi's default "SCP=/dev/null" (EXTRA_OEMAKE:append:sun50i in
# meta-sunxi's own u-boot_%.bbappend) with the crust SCP firmware built by
# recipes-bsp/crust, for orange-pi-3lts only.
#
# make honours whichever SCP= is *last* on the command line, so the
# meta-sunxi-injected "SCP=/dev/null" token has to actually be removed, not
# just out-ordered. First attempt did this by reading EXTRA_OEMAKE back and
# rewriting it in an anonymous python function -- that produced the correct
# string locally (confirmed via `bitbake -e`), but self-referencing a
# variable that other layers also :append to (read X, then setVar X) is a
# known bitbake hash-instability trap: CI's stricter reparse-consistency
# check failed with "the metadata is not deterministic" on this exact
# recipe, which our local build only surfaced as an unread WARNING. Use
# pure declarative :remove/:append instead -- no self-reference, no python,
# no reparse-hash risk. :remove strips the literal "SCP=/dev/null" token
# bitbake tracks it splits on whitespace; :append (after it, same file, same
# override) adds ours.
DEPENDS:append:orange-pi-3lts = " crust-firmware"
do_compile:orange-pi-3lts[depends] += "crust-firmware:do_deploy"

EXTRA_OEMAKE:remove:orange-pi-3lts = "SCP=/dev/null"
EXTRA_OEMAKE:append:orange-pi-3lts = " SCP=${DEPLOY_DIR_IMAGE}/scp.bin"
