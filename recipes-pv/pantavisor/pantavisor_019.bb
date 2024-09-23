#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "Pantavisor Next Gen System Runtime"
SECTION = "base"
DEPENDS = "cmake libthttp picohttpparser lxc-pv mbedtls zlib pkgconfig-native"
RDEPENDS:${PN} += "lxc-pv e2fsprogs-resize2fs e2fsprogs-e2fsck e2fsprogs-mke2fs cryptsetup libthttp-certs gptfdisk "
RDEPENDS:${PN}:qemumips += "lxc-pv libthttp-certs "
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}_${PV}:"

S = "${WORKDIR}/git"

SRC_URI = "git://github.com/pantavisor/pantavisor.git;protocol=https;nobranch=1"
SRC_URI += " file://pantavisor-run"
SRC_URI += " file://rev0json"

SRCREV = "88c3e58e75ce8117994148f52d1790addfcda8f1"

FILES:${PN} += " /usr/bin/pantavisor-run"
FILES:${PN} += " /usr/lib"
FILES:${PN} += " /var/pantavisor/storage/trails/0/.pvr/json"
FILES:${PN} += " /usr/share/pantavisor/skel/etc/pantavisor/defaults/groups.json"
FILES:${PN} += " /storage /writable /volumes /exports /pv /etc/pantavisor /lib/ "
FILES:${PN} += " /certs"
FILES:${PN} += " /init"

inherit cmake

EXTRA_OECMAKE += "${@bb.utils.contains('DISTRO_FEATURES', 'usrmerge', '-DPANTAVISOR_USRMERGE=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-crypt', '-DPANTAVISOR_DM_CRYPT=ON', '', d)}"
EXTRA_OECMAKE += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-verity', '-DPANTAVISOR_DM_VERITY=ON', '', d)}"
EXTRA_OECMAKE += "-DPANTAVISOR_PVS_SKIP_INSTALL=ON"

OECMAKE_C_FLAGS += "-Wno-unused-result -ldl -DPANTAVISOR_DEBUG=ON"

CMAKE_BINARY_DIR = "${S}"

do_install() {
	cmake_do_install
	install -d ${D}/etc
	install -d ${D}/etc/pantavisor
	install -d ${D}/usr/share/pantavisor/skel/etc/pantavisor/defaults
	install -d ${D}/usr/share/pantavisor/skel/writable
	install -d ${D}/usr/share/pantavisor/skel/storage
	install -d ${D}/usr/share/pantavisor/skel/exports
	install -d ${D}/usr/share/pantavisor/skel/configs
	install -d ${D}/usr/share/pantavisor/skel/etc/dropbear
	install -d ${D}/usr/share/pantavisor/skel/volumes
	install -d ${D}/usr/share/pantavisor/skel/pv
	install -d ${D}/usr/share/pantavisor/skel/old
	install -d ${D}/storage
	install -d ${D}/volumes
	install -d ${D}/exports
	install -d ${D}/writable
	install -d ${D}/pv
	install -d ${D}/var/pantavisor/storage/trails/0/.pvr
	install -d ${D}/var/pantavisor/storage/config
	install -d ${D}/var/pantavisor/storage/boot
	install -d ${D}/var/pantavisor/storage/disks
	install -d ${D}/var/pantavisor/root
	install -d ${D}/var/pantavisor/tmpfs
	install -d ${D}/var/pantavisor/ovl/work
	install -d ${D}/var/pantavisor/ovl/upper
	install -d ${D}/usr/lib
	install -m 0644 ${S}/defaults/groups.json ${D}/usr/share/pantavisor/skel/etc/pantavisor/defaults/groups.json
	install -m 0644 ${WORKDIR}/rev0json ${D}/var/pantavisor/storage/trails/0/.pvr/json
	install -m 0755 ${WORKDIR}/pantavisor-run ${D}/usr/bin/pantavisor-run
	install -m 0755 ${WORKDIR}/pantavisor-run ${D}/usr/bin/pantavisor-run
	if [ -f ${WORKDIR}/pantavisor-installer ]; then
		install -m 0755 ${WORKDIR}/pantavisor-installer ${D}/lib/pv/pantavisor-installer
	fi
	[ -f ../../lib/pv ] && ln -sf ../../lib/pv ${D}/usr/lib/pv
	echo "Yes"
}

