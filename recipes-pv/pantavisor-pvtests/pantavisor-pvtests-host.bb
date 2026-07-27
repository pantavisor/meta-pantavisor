SUMMARY = "PVtests host-side orchestrator and shared helpers"
DESCRIPTION = "test.docker.sh, the orchestrator that runs on the CI/developer host \
outside every container, together with the devices.txt manifest template, the \
workspace README and the pvtest/common helpers it shares with the in-container \
runner. Deployed, not packaged: these run on the host, never inside an image."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

SRC_URI = " \
	file://host \
	file://pvtest \
"

do_install[noexec] = "1"

# Deployed under pvtests/ because pantavisor-appengine-distro's do_create_tarball
# copies ${DEPLOY_DIR_IMAGE}/pvtests/. into the tarball root — the same channel
# the local/ and remote/ suites already use. That puts common at
# <tarball-root>/pvtest/common, which is where test.docker.sh sources it from
# ("$(dirname "$0")/pvtest/common").
do_deploy() {
    install -d ${DEPLOYDIR}/pvtests
    install -m 0755 ${WORKDIR}/host/test.docker.sh ${DEPLOYDIR}/pvtests/test.docker.sh
    install -m 0644 ${WORKDIR}/host/devices.txt    ${DEPLOYDIR}/pvtests/devices.txt
    install -m 0644 ${WORKDIR}/host/README.md      ${DEPLOYDIR}/pvtests/README.md

    install -d ${DEPLOYDIR}/pvtests/pvtest
    install -m 0644 ${WORKDIR}/pvtest/common ${DEPLOYDIR}/pvtests/pvtest/common
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}/pvtests"
