LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

DOCKER_IMAGE_NAME = "${PN}"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

CORE_IMAGE_EXTRA_INSTALL += " \
	curl \
	jq \
	pantavisor-pvtest \
	procps \
	pvr \
"

PV_DOCKER_IMAGE_ENVS = 'TEST_PATH="/" INTERACTIVE="false" MANUAL="false" OVERWRITE="false" VERBOSE="false" NETSIM="false"'
PV_DOCKER_IMAGE_ENTRYPOINT_ARGS = '-c "/usr/bin/pvtest-run $TEST_PATH $INTERACTIVE $MANUAL $OVERWRITE $VERBOSE $NETSIM"'

SRC_URI += "\
"

do_install_scripts:append() {
    echo "Starting Install of appengine tester"
}

