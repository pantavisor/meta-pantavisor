SUMMARY = "Pantavisor IPAM Test - Pool-using container on pvcnet"
DESCRIPTION = "A minimal container that attaches to the `pvcnet` pool via PV_NETWORK_POOL. Paired with pv-example-device-ipam-lxcbr + pv-example-ipam-static to exercise pantavisor's reservation walk: the static-IP container bakes 10.0.3.2 in its lxc.container.conf, so the reservation walk must prevent pvcnet from allocating the same address to this container (which should get 10.0.3.3)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-example-net-pvcnet"

IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-ipam-test.sh \
            file://pv-example-net-pvcnet.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-ipam-test.sh ${IMAGE_ROOTFS}${bindir}/pv-ipam-test
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-ipam-test"
