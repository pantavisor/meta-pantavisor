SUMMARY = "Example DRM Service Provider"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image-pvrexport

IMAGE_BASENAME = "pv-example-drm-provider"

SRC_URI += "file://${PN}.services.json"

IMAGE_INSTALL += "libdrm"
