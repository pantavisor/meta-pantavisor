#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "Pantavisor Example Config Package"
SECTION = "base"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvr-ca

SRC_URI += "file://etcdir-embedded/"

do_install() {
	cp -rf ${WORKDIR}/etcdir-embedded ${D}/etc
}

