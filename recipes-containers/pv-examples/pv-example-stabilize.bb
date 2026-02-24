# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Pantavisor Example Stabilize Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-stabilize"

IMAGE_INSTALL += "busybox"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://pv-stabilize.sh file://pv-example-stabilize.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-stabilize.sh ${IMAGE_ROOTFS}${bindir}/pv-stabilize
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

FILES:${PN} += "${bindir}/pv-stabilize"

# Ensure busybox is present for the script
IMAGE_INSTALL:append = " busybox"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-stabilize"