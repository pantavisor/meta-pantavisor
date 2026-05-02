SUMMARY = "Agentic camera analyzer — subscribes to camera-feed, emits detection/OCR events"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "agentic-camera-analyzer"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-json python3-netserver busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://agentic-camera-analyzer.py \
            file://${PN}.services.json \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/agentic-camera-analyzer.py ${IMAGE_ROOTFS}${bindir}/agentic-camera-analyzer
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/agentic-camera-analyzer --config=Cmd=/run/camera/analysis.sock"
