SUMMARY = "A lightweight SSH implementation for Pantavisor"
HOMEPAGE = "https://pantavisor.io"
DESCRIPTION = "Dropbear Pantavisor is a dropbear fork with features to allow a multi container ssh experience for Pantavisor systems."
SECTION = "console/network"

# some files are from other projects and have others license terms:
#   public domain, OpenSSH 3.5p1, OpenSSH3.6.1p2, PuTTY
LICENSE = "MIT & BSD-3-Clause & BSD-2-Clause & PD"
LIC_FILES_CHKSUM = "file://LICENSE;md5=25cf44512b7bc8966a48b6b1a9b7605f"

DEPENDS = "zlib virtual/crypt"
RPROVIDES:${PN} = "ssh sshd"
RCONFLICTS:${PN} = "openssh-sshd openssh"

# break dependency on base package for -dev package
# otherwise SDK fails to build as the main openssh and dropbear packages
# conflict with each other
RDEPENDS:${PN}-dev = ""

SRC_URI = "git://github.com/pantacor/dropbear-pv;branch=pv/master;protocol=https"
SRCREV = "9665557b28c687d66a9203f0c77706ad10994e03"

S = "${WORKDIR}/git"

inherit autotools

CVE_PRODUCT = "dropbear_ssh"

SBINCOMMANDS = "dropbear dropbearkey dropbearconvert"
BINCOMMANDS = "dbclient ssh scp"
EXTRA_OEMAKE = 'MULTI=1 SCPPROGRESS=1 PROGRAMS="${SBINCOMMANDS} ${BINCOMMANDS}"'

# This option appends to CFLAGS and LDFLAGS from OE
# This is causing [textrel] QA warning
EXTRA_OECONF += "--disable-harden"

# musl does not implement wtmp/logwtmp APIs
EXTRA_OECONF:append:libc-musl = " --disable-wtmp --disable-lastlog"

do_install() {
	install -d ${D}${sysconfdir} \
		${D}${sysconfdir}/dropbear \
		${D}${bindir} \
		${D}${sbindir} \
		${D}${localstatedir}

	install -m 0755 dropbearmulti ${D}${sbindir}/

	for i in ${BINCOMMANDS}
	do
		# ssh and scp symlinks are created by update-alternatives
		if [ $i = ssh ] || [ $i = scp ]; then continue; fi
		ln -s ${sbindir}/dropbearmulti ${D}${bindir}/$i
	done
	for i in ${SBINCOMMANDS}
	do
		ln -s ./dropbearmulti ${D}${sbindir}/$i
	done
}

inherit update-alternatives

ALTERNATIVE_PRIORITY = "20"
ALTERNATIVE:${PN} = "${@bb.utils.filter('BINCOMMANDS', 'scp ssh', d)}"

ALTERNATIVE_TARGET = "${sbindir}/dropbearmulti"

FILES:${PN} += "${bindir}"
