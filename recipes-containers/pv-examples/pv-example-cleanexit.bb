SUMMARY = "Pantavisor Example Clean Exit Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-cleanexit"

IMAGE_INSTALL += "busybox"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-cleanexit.sh file://pv-example-cleanexit.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-cleanexit.sh ${IMAGE_ROOTFS}${bindir}/pv-cleanexit
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-cleanexit"
