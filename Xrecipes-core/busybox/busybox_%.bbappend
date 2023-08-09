FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

S = "${WORKDIR}/git"

DEPENDS:append = "\
	       libcap \
"

SRC_URI:remove = "\
	https://busybox.net/downloads/busybox-${PV}.tar.bz2;name=tarball \
"

SRC_URI:append = "\
	git://gitlab.com/pantacor/busybox.git;protocol=https;branch=pv/1_31_stable \
"
SRCREV = "cce7e93074e1bc82834d61d582ad2d5295b04f8c"

SRC_URI:append = "\
	file://pantavisor.cfg \
"

