SUMMARY = "Agentic camera stream — webui that visualises the analyzer's output"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "agentic-camera-stream"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-json python3-netserver busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://agentic-camera-stream.py \
            file://agentic-camera-stream.html \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -d ${IMAGE_ROOTFS}${datadir}/agentic-camera-stream
    install -m 0755 ${WORKDIR}/agentic-camera-stream.py ${IMAGE_ROOTFS}${bindir}/agentic-camera-stream
    install -m 0644 ${WORKDIR}/agentic-camera-stream.html ${IMAGE_ROOTFS}${datadir}/agentic-camera-stream/index.html
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

# Serves the web UI on TCP :8080 inside the container's netns.
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/agentic-camera-stream --config=Cmd=8080"
