SUMMARY = "Example D-Bus Service Consumer Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-client"

RDEPENDS:${PN} += "dbus"
IMAGE_INSTALL += "dbus"

SRC_URI += "file://pv-dbus-client.sh \
            file://${PN}.args.json"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-client.sh ${D}${bindir}/pv-dbus-client
}

FILES:${PN} += "${bindir}/pv-dbus-client"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-client"
