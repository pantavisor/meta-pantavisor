# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Example D-Bus Service Provider Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-server"

PVRIMAGE_AUTO_MDEV = "0"



RDEPENDS:${PN} += "dbus"


IMAGE_INSTALL += "dbus python3-core python3-pydbus python3-io busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-dbus-server.py \
            file://pv-dbus-server.sh \
            file://pv-dbus-server.conf \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-server.py ${IMAGE_ROOTFS}${bindir}/pv-dbus-server.py
    install -m 0755 ${WORKDIR}/pv-dbus-server.sh ${IMAGE_ROOTFS}${bindir}/pv-dbus-server

    install -d ${IMAGE_ROOTFS}${sysconfdir}/dbus-1/system.d
    install -m 0644 ${WORKDIR}/pv-dbus-server.conf ${IMAGE_ROOTFS}${sysconfdir}/dbus-1/system.d/org.pantavisor.Example.conf

    install -m 0644 ${WORKDIR}/pv-example-dbus-server.services.json ${IMAGE_ROOTFS}/services.json
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-server"
