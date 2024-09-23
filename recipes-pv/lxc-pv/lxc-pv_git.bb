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

# Split off some essential tools to be installed, do not install the rest of the ${bindir}/lxc* tools
PACKAGES =+ "${PN}-essentials ${PN}-noinst"
PACKAGE_EXCLUDE:${PN} = "${PN}-noinst"
RDEPENDS:${PN} += "${PN}-essentials"
FILES:${PN}-essentials = "${bindir}/lxc-console"
FILES:${PN}-essentials += "${bindir}/lxc-info"
FILES:${PN}-essentials += "${bindir}/lxc-ls"
FILES:${PN}-essentials += "${bindir}/lxc-top"
FILES:${PN}-noinst+= " ${bindir}/lxc-*"

FILES:${PN} += " /usr/lib/lxc"
FILES:${PN} += " /usr/var"
FILES:${PN} += " /lib"

SRC_URI = "git://gitlab.com/pantacor/lxc;protocol=https;branch=stable-3.0-BASE-2c5c780762981a5cfe699670c91397e29f6f6516;rev=12b46e8269f6e86b206d8c7a1cd30bc5f322464b \
	file://0001-add-new-config-lxc.tty.min-as-lower-bound-of-tty-all.patch"

S = "${WORKDIR}/git"

EXTRA_OECONF:libc-musl = "--disable-api-docs --enable-static --disable-selinux --with-distro=debian CFLAGS='-Wno-error=strict-prototypes -Wno-error=old-style-definition -Wno-error=stringop-overflow -Wno-error=stringop-overread' --prefix=/usr --localstatedir=/usr/var"
EXTRA_OECONF:libc-glibc = "--disable-api-docs --enable-static --disable-selinux --with-distro=debian CFLAGS='-Wno-error=strict-prototypes -Wno-error=old-style-definition -Wno-error=stringop-overflow -Wno-error=stringop-overread' --prefix=/usr --localstatedir=/usr/var"

inherit autotools pkgconfig

do_install:append() {
    rm -rf ${D}/usr/share
    rm -rf ${D}/lib/systemd
}

