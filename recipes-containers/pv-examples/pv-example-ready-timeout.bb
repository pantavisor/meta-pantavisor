SUMMARY = "Pantavisor Example Ready-Timeout Container"
DESCRIPTION = "Example container with status_goal READY that never sends the \
READY signal, so any update that includes it deterministically times out its \
goals and rolls back. Used by tests that need a controlled status-goal failure \
(e.g. local/runtime/status-goal-success-failure). Counterpart of \
pv-example-ready, which signals as soon as it is up."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-ready-timeout"

IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-ready-timeout.sh file://pv-example-ready-timeout.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ready-timeout.sh ${IMAGE_ROOTFS}${bindir}/pv-ready-timeout
    install -d -m 1777 ${IMAGE_ROOTFS}/tmp
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ready-timeout"
PVR_APP_ADD_ROLES = "nobody"
