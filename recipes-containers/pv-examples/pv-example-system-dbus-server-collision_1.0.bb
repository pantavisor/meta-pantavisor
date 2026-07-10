SUMMARY = "Second owner of org.pantavisor.Example — provokes a hosted-bus name collision"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-system-dbus-server-collision"

PVRIMAGE_AUTO_MDEV = "0"

# Deliberately minimal: this container never runs a real D-Bus server. It only
# ships a services.json that declares ownership of org.pantavisor.Example on the
# hosted system-bus with a DIFFERENT role than pv-example-system-dbus-server.
# Placing both owners in one revision makes pv_dbus_daemon_validate() reject the
# state ("owned by more than one app") before any container runs — the revision
# errors and rolls back. A busybox sleep loop is all the payload we need.
IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-app.sh \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-app.sh ${IMAGE_ROOTFS}${bindir}/pv-app
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-app"
