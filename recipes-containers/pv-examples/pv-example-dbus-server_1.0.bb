SUMMARY = "Example D-Bus Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-server"

RDEPENDS:${PN} += "dbus"
IMAGE_INSTALL += "dbus python3-core python3-pydbus python3-io busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-dbus-server.py \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-server.py ${IMAGE_ROOTFS}${bindir}/pv-dbus-server
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-server"
