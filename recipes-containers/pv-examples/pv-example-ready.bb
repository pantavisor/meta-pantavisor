SUMMARY = "Pantavisor Example Ready-Signaling Container"
DESCRIPTION = "Example container with status_goal READY that signals READY as \
soon as it starts. Used by tests that need an update to succeed through the \
status-goal mechanism (e.g. local/runtime/status-goal-success-failure). \
Counterpart of pv-example-ready-timeout, which never signals."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-ready"

IMAGE_INSTALL = "busybox coreutils curl"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-ready.sh file://pv-example-ready.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ready.sh ${IMAGE_ROOTFS}${bindir}/pv-ready
    install -d -m 1777 ${IMAGE_ROOTFS}/tmp
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ready"
PVR_APP_ADD_ROLES = "nobody"
