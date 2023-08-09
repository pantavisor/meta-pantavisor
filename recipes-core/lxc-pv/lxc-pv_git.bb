DESCRIPTION = "lxc aims to use these new functionnalities to provide an userspace container object"
SECTION = "console/utils"
LICENSE = "CLOSED"

DEPENDS = "libxml2 libcap"
RDEPENDS_${PN} = " \
		rsync \
		curl \
		gzip \
		xz \
		tar \
		libcap-bin \
		bridge-utils \
		dnsmasq \
		perl-module-strict \
		perl-module-getopt-long \
		perl-module-vars \
		perl-module-exporter \
		perl-module-constant \
		perl-module-overload \
		perl-module-exporter-heavy \
		gmp \
		libidn \
		gnutls \
		nettle \
		util-linux-mountpoint \
		util-linux-getopt \
"

FILES:${PN} += " /usr/bin/lxc-*"
FILES:${PN} += " /usr/lib/lxc"
FILES:${PN} += " /usr/var"
FILES:${PN} += " /lib"

SRC_URI = "git://gitlab.com/pantacor/lxc;protocol=https;branch=stable-3.0-BASE-2c5c780762981a5cfe699670c91397e29f6f6516;rev=132558831e3f65dccb502cc749ec855b843387b2"

S = "${WORKDIR}/git"

EXTRA_OECONF:libc-musl = "--disable-api-docs --enable-static --disable-selinux --with-distro=debian CFLAGS='-O2 -Wno-error=strict-prototypes -Wno-error=old-style-definition -Wno-error=stringop-overflow' --prefix=/usr --localstatedir=/usr/var"
EXTRA_OECONF:libc-glibc = "--disable-api-docs --enable-static --disable-selinux --with-distro=debian CFLAGS='-Wno-error=strict-prototypes -Wno-error=old-style-definition -Wno-error=stringop-overflow' --prefix=/usr --localstatedir=/usr/var"

inherit autotools pkgconfig

do_install:append() {
    rm -rf ${D}/usr/share
    rm -rf ${D}/lib/systemd
}

