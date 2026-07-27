SUMMARY = "PVtests remote test suite data"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

# See pantavisor-pvtests-local.bb for why the source tree has a data/ level and
# the deployed tarball layout does not.
SRC_URI = "file://data/remote;subdir=pvtests"

do_install[noexec] = "1"

do_deploy() {
    install -d ${DEPLOYDIR}/pvtests
    cp -r ${WORKDIR}/pvtests/remote ${DEPLOYDIR}/pvtests/
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}/pvtests"
