SUMMARY = "Pantavisor Example No-Role Container"
DESCRIPTION = "Example container with pvcontrol but running under the 'nobody' \
(non-management) role. Used in security tests to verify that containers without \
the mgmt role are correctly denied management access per the container roles spec: \
https://docs.pantahub.com/pantavisor-src/docs/overview/containers/#roles"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-norole"

IMAGE_INSTALL = "busybox coreutils curl"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-app.sh"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-app.sh ${IMAGE_ROOTFS}${bindir}/pv-app
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-app"
PVR_APP_ADD_ROLES = "nobody"
