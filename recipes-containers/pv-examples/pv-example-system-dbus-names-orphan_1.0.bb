SUMMARY = "Example hosted-bus D-Bus consumer whose names requirement names nobody in the state — provokes a validation failure"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-system-dbus-names-orphan"

PVRIMAGE_AUTO_MDEV = "0"

# Single-pid consumer: no dbus-daemon, no real D-Bus calls. Its names-form
# requirement names org.pantavisor.NoSuchService, which nobody in the state
# owns, so pv_state_validate_services() rejects the state before any
# container runs — the revision errors and rolls back. A busybox sleep loop
# is all the payload we need.
IMAGE_INSTALL += "busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-app.sh \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-app.sh ${IMAGE_ROOTFS}${bindir}/pv-app
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-app"
