SUMMARY = "Example REST Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-rest-server"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-netserver python3-json busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-rest-server.py \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-rest-server.py ${IMAGE_ROOTFS}${bindir}/pv-rest-server
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

# OCI/LXC entrypoint
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-rest-server --config=Cmd=/run/nm/api.sock"