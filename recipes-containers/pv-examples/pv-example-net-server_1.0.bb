SUMMARY = "Example Network Server Container"
DESCRIPTION = "A simple HTTP server using IPAM pool networking"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-net-server"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-json python3-netserver busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-net-server.py \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-net-server.py ${IMAGE_ROOTFS}${bindir}/pv-net-server
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

# OCI/LXC entrypoint
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-net-server"
