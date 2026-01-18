SUMMARY = "Example D-Bus Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-server"

RDEPENDS:${PN} += "dbus"
IMAGE_INSTALL += "dbus python3-core python3-pydbus python3-io"

SRC_URI += "file://pv-dbus-server.py \
            file://${PN}.services.json"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-server.py ${D}${bindir}/pv-dbus-server
}

FILES:${PN} += "${bindir}/pv-dbus-server"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-server"
