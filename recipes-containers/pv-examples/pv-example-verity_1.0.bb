SUMMARY = "Pantavisor Example dm-verity Container"
DESCRIPTION = "Test container whose root volume is protected with dm-verity. \
It runs the same small script as pv-example-ready and signals READY as soon \
as it starts, so a device test can tell that the protected volume was mounted \
and the container came up."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-verity"

IMAGE_INSTALL = "busybox coreutils curl"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

# always protect root.squashfs, even if a distro turns the default off
PVR_DM_VERITY = "1"

SRC_URI += "file://pv-ready.sh file://pv-example-verity.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ready.sh ${IMAGE_ROOTFS}${bindir}/pv-ready
    install -d -m 1777 ${IMAGE_ROOTFS}/tmp
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ready"
PVR_APP_ADD_ROLES = "nobody"
