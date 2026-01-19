SUMMARY = "Example DRM Service Provider"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-drm-provider"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "libdrm busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://${PN}.services.json"
