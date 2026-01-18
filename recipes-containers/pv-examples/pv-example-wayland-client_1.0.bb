SUMMARY = "Example Wayland Client Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image-pvrexport

IMAGE_BASENAME = "pv-example-wayland-client"

RDEPENDS:${PN} += "wayland-utils"
IMAGE_INSTALL += "wayland-utils"

SRC_URI += "file://pv-wayland-client.sh \
            file://${PN}.config.json"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-wayland-client.sh ${D}${bindir}/pv-wayland-client
}

FILES:${PN} += "${bindir}/pv-wayland-client"

PVR_APP_ADD_EXTRA_ARGS += "--entrypoint /usr/bin/pv-wayland-client"