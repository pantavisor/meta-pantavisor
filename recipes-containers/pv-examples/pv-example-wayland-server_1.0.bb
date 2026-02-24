# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Example Wayland Server Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-wayland-server"
PVRIMAGE_AUTO_MDEV = "0"

RDEPENDS:${PN} += "weston"
IMAGE_INSTALL += "weston busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://${PN}.services.json \
            file://${PN}.args.json \
            file://pv-weston-start.sh"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-weston-start.sh ${IMAGE_ROOTFS}${bindir}/pv-weston-start
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-weston-start"
