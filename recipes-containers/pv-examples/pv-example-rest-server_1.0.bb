SUMMARY = "Example REST Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image-pvrexport

IMAGE_BASENAME = "pv-example-rest-server"

RDEPENDS:${PN} += "python3-core python3-netserver"

SRC_URI += "file://pv-rest-server.py \
            file://${PN}.services.json"

IMAGE_INSTALL += "python3-core python3-netserver"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-rest-server.py ${D}${bindir}/pv-rest-server
}

FILES:${PN} += "${bindir}/pv-rest-server"

# OCI/LXC entrypoint
PVR_APP_ADD_EXTRA_ARGS += "--entrypoint /usr/bin/pv-rest-server --args /run/nm/api.sock"