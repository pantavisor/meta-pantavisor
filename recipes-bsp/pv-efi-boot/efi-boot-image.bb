# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "EFI boot partition image for Pantavisor (A/B slots)"
DESCRIPTION = "Produces a vfat image containing the stage-2 bootloader \
(pvboot.efi) and the Unified Kernel Image (pv-linux.efi). \
WIC rawcopy copies this image into both A and B boot partitions."
LICENSE = "MIT"

inherit image

IMAGE_FSTYPES = "vfat"
IMAGE_NAME_SUFFIX = ""
IMAGE_ROOTFS_SIZE = "131072"
EXTRA_IMAGECMD:vfat = "-F 32 -S 512 -n PVBOOT"

# No packages — we populate the rootfs manually
IMAGE_INSTALL = ""
IMAGE_LINGUAS = ""
PACKAGE_INSTALL = ""
ROOTFS_BOOTSTRAP_INSTALL = ""

# Suppress image features that distros inject
IMAGE_FEATURES = ""
MACHINE_FEATURES = ""
DISTRO_FEATURES = ""

do_rootfs[depends] += "pv-efi-boot:do_deploy pv-uki:do_deploy"

fakeroot do_rootfs() {
    install -m 0644 ${DEPLOY_DIR_IMAGE}/pvboot-stage2.efi ${IMAGE_ROOTFS}/pvboot.efi
    install -m 0644 ${DEPLOY_DIR_IMAGE}/pv-linux.efi ${IMAGE_ROOTFS}/pv-linux.efi
}
