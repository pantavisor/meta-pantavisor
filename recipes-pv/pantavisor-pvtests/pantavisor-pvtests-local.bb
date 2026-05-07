SUMMARY = "PVtests local test suite data"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

SRC_URI = "file://local"

do_install[noexec] = "1"

do_deploy() {
    install -d ${DEPLOYDIR}/pvtests
    cp -r ${WORKDIR}/local ${DEPLOYDIR}/pvtests/
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}/pvtests"
