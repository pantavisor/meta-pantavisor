SUMMARY = "Example DRM Render Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-drm-render"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-drm-render.sh \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-drm-render.sh ${IMAGE_ROOTFS}${bindir}/pv-drm-render
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-drm-render"
