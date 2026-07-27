LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

# Tester adds significantly more packages on top of base appengine, so
# it gets its own audit reference under a distinct prefix.
PV_MANIFEST_PREFIX = "pv-appengine-tester"
SRC_URI += " file://pv-appengine-tester_panta-appengine-docker-x86_64-scarthgap.manifest.reference.txt"

DOCKER_IMAGE_NAME = "${PN}"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

# curl, jq, openssh-ssh and pvr arrive transitively via pantavisor-pvtest-runner's
# RDEPENDS. bc stays explicit: nothing in the runner uses it, it is an
# interactive-debug convenience. pantavisor-pvtx-tests carries this repo's pvtx
# unit suite, which tools/testing/run-pvtx-tests runs against this image.
CORE_IMAGE_EXTRA_INSTALL += " \
	bc \
	pantavisor-pvtest-runner \
	pantavisor-pvtx-tests \
	procps \
	valgrind \
	vim-xxd \
"

PV_DOCKER_IMAGE_ENVS = 'TEST_PATH="/" INTERACTIVE="false" MANUAL="false" OVERWRITE="false" VERBOSE="false" NETSIM="false" PVTEST_APPENGINES="" PVTEST_SSH_KEY="/tmp/pvtest_id"'
PV_DOCKER_IMAGE_ENTRYPOINT_ARGS = '-c "/usr/bin/pvtest-run $TEST_PATH $INTERACTIVE $MANUAL $OVERWRITE $VERBOSE $NETSIM"'

SRC_URI += "\
"

do_install_scripts:append() {
    echo "Starting Install of appengine tester"
}

