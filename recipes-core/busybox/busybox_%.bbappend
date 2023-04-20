FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

S = "${WORKDIR}/git"

DEPENDS:append = "\
	       libcap \
"

SRC_URI:remove = "\
	https://busybox.net/downloads/busybox-${PV}.tar.bz2;name=tarball \
"

SRC_URI:append = "\
	git://gitlab.com/pantacor/busybox.git;protocol=https;branch=pv/1_35_stable \
"
SRCREV = "8143ead4fc16cdaccd0b5a38b13a4883b3809b7b"

SRC_URI:append = "\
	file://pantavisor.cfg \
"

