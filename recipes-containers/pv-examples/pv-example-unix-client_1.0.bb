SUMMARY = "Example Raw Unix Service Consumer Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-unix-client"

RDEPENDS:${PN} += "socat"
IMAGE_INSTALL += "socat"

SRC_URI += "file://pv-unix-client.sh \
            file://${PN}.args.json"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-unix-client.sh ${D}${bindir}/pv-unix-client
}

FILES:${PN} += "${bindir}/pv-unix-client"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-unix-client"
