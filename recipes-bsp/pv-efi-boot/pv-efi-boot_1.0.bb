# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Pantavisor EFI Boot Loader - Stage 1 and Stage 2"
DESCRIPTION = "Two-stage UEFI boot loader for Pantavisor A/B partition \
switching using RPi-compatible autoboot.txt syntax."
HOMEPAGE = "https://pantavisor.io"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "gnu-efi"

COMPATIBLE_HOST = "x86_64.*-linux"

SRC_URI = " \
    file://src \
    file://Makefile \
    file://autoboot.txt \
"

S = "${WORKDIR}"

inherit deploy

# gnu-efi installs to the cross sysroot under these paths
GNUEFI_DIR = "${STAGING_DIR_TARGET}/usr"

do_compile() {
    oe_runmake \
        CC="${CC}" \
        LD="${LD}" \
        OBJCOPY="${OBJCOPY}" \
        ARCH="x86_64" \
        GNUEFI_DIR="${GNUEFI_DIR}"
}

do_install() {
    install -d ${D}${datadir}/pv-efi-boot
    install -m 0644 ${S}/stage1.efi ${D}${datadir}/pv-efi-boot/pvboot-stage1.efi
    install -m 0644 ${S}/stage2.efi ${D}${datadir}/pv-efi-boot/pvboot-stage2.efi
    install -m 0644 ${S}/autoboot.txt ${D}${datadir}/pv-efi-boot/autoboot.txt
}

do_deploy() {
    install -m 0644 ${S}/stage1.efi ${DEPLOYDIR}/pvboot-stage1.efi
    install -m 0644 ${S}/stage2.efi ${DEPLOYDIR}/pvboot-stage2.efi
    install -m 0644 ${S}/set-tryboot.efi ${DEPLOYDIR}/pvboot-set-tryboot.efi
    install -m 0644 ${S}/autoboot.txt ${DEPLOYDIR}/autoboot.txt
}

addtask deploy after do_compile before do_build

FILES:${PN} = "${datadir}/pv-efi-boot"
