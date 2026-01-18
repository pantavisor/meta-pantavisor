SUMMARY = "Example Wayland Server Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-wayland-server"

RDEPENDS:${PN} += "weston"
IMAGE_INSTALL += "weston"

SRC_URI += "file://${PN}.services.json"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/weston --config=Cmd='--backend=drm-backend.so --socket=wayland-0'"
