SUMMARY = "Mock tunnel server for pv-devicepass WebSocket tunnel testing"
DESCRIPTION = "Python WebSocket server on Unix socket that periodically sends \
JSON commands to pv-devicepass and logs responses. Used to test the tunnel client."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-devicepass-tunnel-mock"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-asyncio python3-json python3-io busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://${PN}.py \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/${PN}.py ${IMAGE_ROOTFS}${bindir}/pv-devicepass-tunnel-mock
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-devicepass-tunnel-mock"
