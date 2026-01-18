SUMMARY = "Example Raw Unix Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image-pvrexport

IMAGE_BASENAME = "pv-example-unix-server"

RDEPENDS:${PN} += "socat"
IMAGE_INSTALL += "socat"

SRC_URI += "file://pv-unix-server.sh \
            file://${PN}.services.json"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-unix-server.sh ${D}${bindir}/pv-unix-server
}

FILES:${PN} += "${bindir}/pv-unix-server"

PVR_APP_ADD_EXTRA_ARGS += "--entrypoint /usr/bin/pv-unix-server"