
DESCRIPTION = "Pantavisor pvroot skeleton package"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILES:${PN} += " \
	${root_prefix}/boot/* \
	${root_prefix}/config/* \
	${root_prefix}/factory-pkgs.d/** \
	${root_prefix}/logs/** \
	${root_prefix}/objects/* \
	${root_prefix}/trails/** \
"

SRC_URI += " \
	file://device.json \
	file://pantahub.config \
	file://pvrconfig \
	file://uboot.txt \
"

do_install() {
    install -d -m 0755 ${D}/boot
    install -d -m 0755 ${D}/config
    install -d -m 0755 ${D}/factory-pkgs.d
    install -d -m 0755 ${D}/trails
    install -d -m 0755 ${D}/trails/0/.pvr
    install -d -m 0755 ${D}/trails/0/.pv
    install -d -m 0755 ${D}/logs
    install -m 0755 ${WORKDIR}/device.json ${D}/trails/0/.pvr/json
    install -m 0755 ${WORKDIR}/uboot.txt ${D}/boot/uboot.txt
    install -m 0755 ${WORKDIR}/pvrconfig ${D}/trails/0/.pvr/json
    install -m 0755 ${WORKDIR}/pantahub.config ${D}/config/
}
