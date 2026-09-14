SUMMARY = "Control Gembird SIS-PM programmable power outlet strips"
DESCRIPTION = "Command line tool to switch the sockets of GEMBIRD SiS-PM \
power strips, used to power-cycle boards under test."
HOMEPAGE = "https://sispmctl.sourceforge.net/"

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://COPYING;md5=b234ee4d69f5fce4486a80fdaf4a4263"

# labutils pins github.com/asac/sispmctl-mirror, which stopped at 4.8 (2020) and
# still uses AM_CONFIG_HEADER — removed in automake 1.13, so it cannot
# autoreconf here. xypron is sispmctl's upstream author; take the release from
# there instead.
SRC_URI = "git://github.com/xypron/sispmctl.git;protocol=https;branch=master"
SRCREV = "dee19a02eaeaab27779c1b4605ee4138e488d56d"
PV = "4.11"

S = "${WORKDIR}/git"

DEPENDS = "libusb-compat"

inherit autotools pkgconfig

# Makefile.am sets ACLOCAL_AMFLAGS = -I m4 but the directory is not in the
# tree, and aclocal errors out on a missing include dir.
do_configure:prepend() {
    mkdir -p ${S}/m4
}

# sispmctl embeds an HTTP server and three sets of web skins. A lab container
# drives it from the command line only.
EXTRA_OECONF = "--enable-webless"
