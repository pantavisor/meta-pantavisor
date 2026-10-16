SUMMARY = "httpd-only busybox for the pvr SDK"
DESCRIPTION = "A busybox built with the httpd applet and nothing else, installed as \
/usr/sbin/httpd. The pvr SDK's web API (pvr-sdk-httpd, pv-httpd, the pvtx CGI \
scripts) is written against busybox httpd, which the distro's busybox does not \
enable; a separate binary keeps that out of every other image."
HOMEPAGE = "https://busybox.net"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=de10de48642ab74318e893a61105afbb"

SRC_URI = "https://busybox.net/downloads/busybox-${PV}.tar.bz2;name=tarball \
    file://httpd.cfg \
"
SRC_URI[tarball.sha256sum] = "b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314"

S = "${WORKDIR}/busybox-${PV}"

inherit cml1

EXTRA_OEMAKE = "CC='${CC}' LD='${CCLD}' V=1 ARCH=${TARGET_ARCH} CROSS_COMPILE=${TARGET_PREFIX} SKIP_STRIP=y HOSTCC='${BUILD_CC}' HOSTCPP='${BUILD_CPP}'"

do_configure() {
    export KCONFIG_NOTIMESTAMP=1
    oe_runmake allnoconfig
    # Kconfig will not reassign a symbol allnoconfig already wrote.
    for sym in $(sed -n 's/^\(CONFIG_[A-Z0-9_]*\)=.*/\1/p' ${WORKDIR}/httpd.cfg); do
        sed -i -e "/^${sym}=/d" -e "/^# ${sym} is not set/d" .config
    done
    cat ${WORKDIR}/httpd.cfg >> .config
    yes '' | oe_runmake oldconfig
    grep -q '^CONFIG_HTTPD=y' .config
}

do_compile() {
    export KCONFIG_NOTIMESTAMP=1
    # busybox's Makefile takes toolchain flags through EXTRA_*, not the
    # environment's CFLAGS/LDFLAGS.
    oe_runmake EXTRA_CFLAGS="${CFLAGS}" EXTRA_LDFLAGS="${LDFLAGS}" busybox_unstripped
}

# With a single applet compiled in, busybox dispatches on argv[0], so the
# binary only has to be called httpd.
do_install() {
    install -d ${D}${sbindir}
    install -m 0755 ${B}/busybox_unstripped ${D}${sbindir}/httpd
}
