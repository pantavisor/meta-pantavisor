# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Example Network Client Container"
DESCRIPTION = "A simple HTTP client using IPAM pool networking"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-net-client"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "curl busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-net-client.sh \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-net-client.sh ${IMAGE_ROOTFS}${bindir}/pv-net-client
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

# OCI/LXC entrypoint
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-net-client"
