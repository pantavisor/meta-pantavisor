SUMMARY = "PVtests local test suite data"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

# The suites live under files/data/ so each of the three roles in this recipe
# directory (runner, host orchestrator, suite data) owns one subdir.
#
# subdir= sets the unpack prefix; bitbake keeps the SRC_URI path segments under
# it, so files/data/local lands at ${WORKDIR}/pvtests/data/local.
SRC_URI = "file://data/local;subdir=pvtests"

do_install[noexec] = "1"

# One shared tree per scope, not one per target: only common/tarballs/ varies by
# target, and test.docker.sh bind-mounts targets/<type>/local/ over
# /work/local/common/tarballs at tester start. common/templates/ varies by scope
# (local vs remote semantics) and is target-invariant, so it stays here.
do_deploy() {
    install -d ${DEPLOYDIR}/pvtests
    cp -r ${WORKDIR}/pvtests/data/local ${DEPLOYDIR}/pvtests/
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}/pvtests"
