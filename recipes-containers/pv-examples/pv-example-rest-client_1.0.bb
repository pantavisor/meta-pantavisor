SUMMARY = "Example REST Service Consumer Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-rest-client"

RDEPENDS:${PN} += "curl"

SRC_URI += "file://pv-rest-client.sh \
            file://${PN}.args.json"

IMAGE_INSTALL += "curl"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-rest-client.sh ${D}${bindir}/pv-rest-client
}

FILES:${PN} += "${bindir}/pv-rest-client"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-rest-client"
