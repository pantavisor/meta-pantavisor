SUMMARY = "PVtests remote test suite data"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

# See pantavisor-pvtests-local.bb for why the source tree has a data/ level.
SRC_URI = "file://data/remote;subdir=pvtests"

do_install[noexec] = "1"

# One shared tree per scope, not one per target: only common/tarballs/ varies by
# target, and test.docker.sh bind-mounts targets/<type>/remote/ over
# /work/remote/common/tarballs at tester start. common/templates/ varies by scope
# (local vs remote semantics) and is target-invariant, so it stays here.
do_deploy() {
    install -d ${DEPLOYDIR}/pvtests
    cp -r ${WORKDIR}/pvtests/data/remote ${DEPLOYDIR}/pvtests/
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}/pvtests"
