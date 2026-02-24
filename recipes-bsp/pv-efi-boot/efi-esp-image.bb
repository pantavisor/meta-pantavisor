# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "EFI System Partition (ESP) image for Pantavisor"
DESCRIPTION = "Produces a vfat image containing the stage-1 EFI bootloader \
at the UEFI default boot path (EFI/BOOT/BOOTX64.EFI) plus autoboot.txt. \
WIC rawcopy copies this image verbatim into the ESP partition."
LICENSE = "MIT"

inherit image

IMAGE_FSTYPES = "vfat"
IMAGE_NAME_SUFFIX = ""
IMAGE_ROOTFS_SIZE = "65536"
EXTRA_IMAGECMD:vfat = "-F 32 -S 512 -n ESP"

# No packages — we populate the rootfs manually
IMAGE_INSTALL = ""
IMAGE_LINGUAS = ""
PACKAGE_INSTALL = ""
ROOTFS_BOOTSTRAP_INSTALL = ""

# Suppress image features that distros inject
IMAGE_FEATURES = ""
MACHINE_FEATURES = ""
DISTRO_FEATURES = ""

do_rootfs[depends] += "pv-efi-boot:do_deploy"

fakeroot do_rootfs() {
    install -d ${IMAGE_ROOTFS}/EFI/BOOT
    install -m 0644 ${DEPLOY_DIR_IMAGE}/pvboot-stage1.efi ${IMAGE_ROOTFS}/EFI/BOOT/BOOTX64.EFI
    install -m 0644 ${DEPLOY_DIR_IMAGE}/autoboot.txt ${IMAGE_ROOTFS}/autoboot.txt
}
