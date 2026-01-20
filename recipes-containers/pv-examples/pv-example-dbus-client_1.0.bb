SUMMARY = "Example D-Bus Service Consumer Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-client"

RDEPENDS:${PN} += "dbus"
IMAGE_INSTALL += "dbus busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-dbus-client.sh \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-client.sh ${IMAGE_ROOTFS}${bindir}/pv-dbus-client
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-client"
