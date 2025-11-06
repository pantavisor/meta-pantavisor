#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "Pantavisor Next Gen System Runtime"
SECTION = "base"
DEPENDS = "cmake libevent libthttp picohttpparser lxc-pv mbedtls zlib pkgconfig-native"
RDEPENDS:${PN} += "lxc-pv \
	e2fsprogs-e2fsck \
	e2fsprogs-mke2fs \
	cryptsetup \
	libthttp-certs \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'runc', 'runc-opencontainers', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'autogrow', 'gptfdisk e2fsprogs-resize2fs', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'appengine', 'bash', '', d)} \
	"
RDEPENDS:${PN}:qemumips += "lxc-pv libthttp-certs "
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}_${PV}:"

S = "${WORKDIR}/git"

PANTAVISOR_BRANCH ??= "feature/appengine-in-tree"

SRC_URI = "git://github.com/pantavisor/pantavisor.git;protocol=https;branch=${PANTAVISOR_BRANCH} \
           file://rev0json \
           "

SRCREV = "7d792dab5ecea30b38c791b300644ae6efd8040d"
PE = "1"
PKGV = "024+git0+${GITPKGV}"

PACKAGES =+ "${PN}-pvtx ${PN}-pvtx-static ${PN}-config ${PN}-pvtest"

FILES:${PN} += " /usr/bin/pantavisor-run"
FILES:${PN} += " /usr/lib"
FILES:${PN} += " /usr/share/pantavisor/skel/etc/pantavisor/defaults/groups.json"
FILES:${PN} += " /writable /volumes /exports /pv /etc/pantavisor /lib/ "
FILES:${PN} += " /init"

# pvtx packages
FILES:${PN}-pvtx += " ${bindir}/pvtx"
FILES:${PN}-pvtx-static += " ${bindir}/pvtx-static"

FILES:${PN}-config += "/etc/pantavisor-appengine.config"
FILES:${PN}-config += "/etc/pantavisor.config"
FILES:${PN}-config += "/etc/pantavisor/"
FILES:${PN}-config += "/etc/resolv.conf"

FILES:${PN}-pvtest += "/usr/bin/pvtest-run"
FILES:${PN}-pvtest += "/usr/share/pantavisor/pvtest/utils"

inherit cmake gitpkgv

EXTRA_OECMAKE += "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '-DPANTAVISOR_USRMERGE=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'debug', '-DPANTAVISOR_DEBUG=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-crypt', '-DPANTAVISOR_DM_CRYPT=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-verity', '-DPANTAVISOR_DM_VERITY=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'autogrow', '-DPANTAVISOR_E2FSGROW_ENABLE=ON', '-DPANTAVISOR_E2FSGROW_ENABLE=OFF', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'runc', '-DPANTAVISOR_RUNC_ENABLE=ON', '-DPANTAVISOR_RUNC_ENABLE=OFF', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'appengine', '-DPANTAVISOR_APPENGINE=ON', '-DPANTAVISOR_APPENGINE=OFF', d)}"
EXTRA_OECMAKE += '-DPANTAVISOR_DISTRO_NAME="${DISTRO_NAME}"'
EXTRA_OECMAKE += '-DPANTAVISOR_DISTRO_VERSION="${DISTRO_VERSION}"'
EXTRA_OECMAKE += '-DPANTAVISOR_PVTEST=ON'
EXTRA_OECMAKE += "-DPANTAVISOR_PVTX_STATIC=ON -DPANTAVISOR_PVTX=ON -DPANTAVISOR_RUNTIME=ON"

OECMAKE_C_FLAGS += "-Wno-unused-result -ldl -Wno-error=implicit-function-declaration"

CMAKE_BINARY_DIR = "${S}"
do_install() {
	cmake_do_install
	# [ -f ../../lib/pv ] && ln -sf ../../lib/pv ${D}/usr/lib/pv
	echo "Yes"
}

