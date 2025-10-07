LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

DOCKER_IMAGE_NAME = "${PN}"
DOCKER_IMAGE_TAG = "1.0"

PV_DOCKER_IMAGE_ENVS = 'TEST_PATH="/" INTERACTIVE="false" MANUAL="false" OVERWRITE="false" VERBOSE="false" NETSIM="false"'
PV_DOCKER_IMAGE_ENTRYPOINT_ARGS = '-c "/usr/local/bin/pv-appengine-tester_run-test $TEST_PATH $INTERACTIVE $MANUAL $OVERWRITE $VERBOSE $NETSIM"'

SRC_URI += "\
	file://pv-appengine-tester_run-test.sh \
	file://pv-appengine-tester_utils \
"

do_install_scripts:append() {

    echo "Starting Install of appengine tester"

    mkdir -p ${IMAGE_ROOTFS}/usr/local/bin
    install -m 0755 ${WORKDIR}/pv-appengine-tester_run-test.sh ${IMAGE_ROOTFS}/usr/local/bin/pv-appengine-tester_run-test

    mkdir -p ${IMAGE_ROOTFS}/usr/local/share/pantavisor-appengine-tester/
    install -m 0755 ${WORKDIR}/pv-appengine-tester_utils ${IMAGE_ROOTFS}/usr/local/share/pantavisor-appengine-tester/utils

}

