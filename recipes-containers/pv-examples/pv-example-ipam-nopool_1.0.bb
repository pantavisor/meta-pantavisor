SUMMARY = "Pantavisor IPAM Test - Unknown Pool Reference"
DESCRIPTION = "Tests IPAM with a reference to a pool that does not exist in device.json. Must cause pv_platform_start to refuse, propagating to pv_state_run → rollback (if TESTING) or reboot (steady state). The entrypoint is a defensive idle loop — it should never actually run because pantavisor rejects the container before launch."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-ipam-nopool"

IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-ipam-test.sh file://pv-example-ipam-nopool.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ipam-test.sh ${IMAGE_ROOTFS}${bindir}/pv-ipam-test
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ipam-test"
