SUMMARY = "Pantavisor IPAM Test - Legacy container with baked lxc.net.* (static IP)"
DESCRIPTION = "A legacy-style LXC container that pins itself to 10.0.5.2/24 on bridge pvbr0 via PV_LXC_NETWORK_* pvr template vars instead of opting into IPAM. Exists to exercise the pantavisor reservation walk: when paired with the `internal` pool (10.0.5.0/24), pantavisor must reserve 10.0.5.2 so the pool allocator skips it for other pool-using containers."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-ipam-static"

IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-ipam-test.sh \
            file://pv-example-ipam-static.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ipam-test.sh ${IMAGE_ROOTFS}${bindir}/pv-ipam-test
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ipam-test"
