DESCRIPTION = "LXC 6.x container library with Pantavisor patches"
SECTION = "console/utils"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=4b6551da9cb7d5b3017d1c0a3e31469b"

DEPENDS = "libcap pkgconfig-native"

SRC_URI = "git://github.com/pantavisor/lxc;protocol=https;branch=stable-6.0-BASE-f9ff9ea2a"
SRCREV = "c2017d421b28fb169ce62ba216b6df2fb07d10cb"

PE = "1"
PV = "6.0.5+git${SRCPV}"

S = "${WORKDIR}/git"

inherit meson pkgconfig

# Override localstatedir to match Pantavisor's PV_SYSTEM_USRDIR=/usr
# This ensures lxc-ls looks in /usr/var/lib/lxc where Pantavisor creates containers
localstatedir = "/usr/var"

# Meson options - disable optional features we don't need
EXTRA_OEMESON = " \
    -Dapparmor=false \
    -Dselinux=false \
    -Dseccomp=false \
    -Dcapabilities=true \
    -Dexamples=false \
    -Dman=false \
    -Dtests=false \
    -Dtools=true \
    -Dcommands=true \
    -Dinstall-init-files=false \
    -Dinstall-state-dirs=false \
    -Dio-uring-event-loop=false \
    -Ddbus=false \
    -Dpam-cgroup=false \
    -Dopenssl=false \
    -Dthread-safety=true \
    -Dmemfd-rexec=true \
"

# Split off some essential tools to be installed, do not install the rest of the ${bindir}/lxc* tools
PACKAGES =+ "${PN}-essentials ${PN}-noinst"
RDEPENDS:${PN} += "${PN}-essentials"
FILES:${PN}-essentials = "${bindir}/lxc-console ${bindir}/lxc-info ${bindir}/lxc-ls ${bindir}/lxc-top"
FILES:${PN}-noinst = "${bindir}/lxc-*"

FILES:${PN} += " \
    ${libdir}/lxc \
    ${localstatedir} \
    ${datadir}/lxc \
"

do_install:append() {
    # Remove unnecessary files - we don't need templates/hooks/examples
    rm -rf ${D}${datadir}/doc
    rm -rf ${D}${datadir}/bash-completion
    rm -rf ${D}${datadir}/lxc/templates
    rm -rf ${D}${datadir}/lxc/hooks
}
