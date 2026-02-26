SUMMARY = "JSON.sh - a shell JSON parser"
DESCRIPTION = "A pipeable JSON parser written in shell, used by pvtx and other tools."
SECTION = "utils"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://JSON.sh"

S = "${WORKDIR}"

inherit allarch

do_install() {
	install -d ${D}${bindir}
	install -m 0755 ${S}/JSON.sh ${D}${bindir}
}

FILES:${PN} = "${bindir}/JSON.sh"
