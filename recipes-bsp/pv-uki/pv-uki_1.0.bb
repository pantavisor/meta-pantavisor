# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Pantavisor Unified Kernel Image (UKI)"
DESCRIPTION = "Assembles a UKI containing kernel, initramfs, and cmdline \
into a single signed PE/COFF binary using the Linux EFI stub. \
The cmdline.txt is embedded in the UKI so it is covered by any \
Secure Boot signature applied to pv-linux.efi."
HOMEPAGE = "https://pantavisor.io"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "virtual/kernel"

COMPATIBLE_HOST = "x86_64.*-linux"

# cmdline.txt is embedded in the UKI — changing it changes the binary,
# so it is covered by Secure Boot signatures.
SRC_URI = "file://cmdline.txt"

inherit deploy

# The EFI stub from systemd-boot (deployed, not sysrooted)
EFI_STUB = "${DEPLOY_DIR_IMAGE}/linuxx64.efi.stub"

# Kernel from deploy directory
KERNEL_IMAGE = "${DEPLOY_DIR_IMAGE}/bzImage"

# Initramfs: use multiconfig deploy dir when available (set by panta.conf),
# otherwise fall back to main deploy dir.
INITRAMFS_IMAGE_NAME ?= "pantavisor-initramfs"
INITRAMFS_DEPLOY_DIR_IMAGE ?= "${DEPLOY_DIR_IMAGE}"
INITRAMFS_FILE = "${INITRAMFS_DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE_NAME}-${MACHINE}.cpio.gz"

do_configure[noexec] = "1"

do_compile() {
    if [ ! -f "${EFI_STUB}" ]; then
        bbfatal "EFI stub not found at ${EFI_STUB}. Ensure systemd-boot is built."
    fi
    if [ ! -f "${KERNEL_IMAGE}" ]; then
        bbfatal "Kernel image not found at ${KERNEL_IMAGE}."
    fi
    if [ ! -f "${INITRAMFS_FILE}" ]; then
        bbfatal "Initramfs not found at ${INITRAMFS_FILE}."
    fi

    bbnote "Assembling UKI:"
    bbnote "  stub:     ${EFI_STUB}"
    bbnote "  cmdline:  ${WORKDIR}/cmdline.txt"
    bbnote "  kernel:   ${KERNEL_IMAGE}"
    bbnote "  initramfs:${INITRAMFS_FILE}"

    # Extract ImageBase from PE header and compute section VMAs.
    # The UKI spec defines RVAs (0x30000, 0x2000000, 0x3000000) but
    # objcopy --change-section-vma needs absolute VMAs = ImageBase + RVA.
    # systemd-boot v255 uses ImageBase=0x14df90000 so we must account for it.
    eval $(python3 -c "
import struct
with open('${EFI_STUB}', 'rb') as f:
    f.seek(0x3C)
    pe_off = struct.unpack('<I', f.read(4))[0]
    f.seek(pe_off + 4 + 20)
    magic = struct.unpack('<H', f.read(2))[0]
    if magic == 0x20b:
        f.seek(pe_off + 4 + 20 + 24)
        base = struct.unpack('<Q', f.read(8))[0]
    else:
        f.seek(pe_off + 4 + 20 + 28)
        base = struct.unpack('<I', f.read(4))[0]
print('VMA_CMDLINE=0x%x' % (base + 0x30000))
print('VMA_LINUX=0x%x' % (base + 0x2000000))
print('VMA_INITRD=0x%x' % (base + 0x3000000))
")

    bbnote "Section VMAs: cmdline=$VMA_CMDLINE linux=$VMA_LINUX initrd=$VMA_INITRD"

    ${OBJCOPY} \
        --add-section .cmdline=${WORKDIR}/cmdline.txt \
            --change-section-vma .cmdline=$VMA_CMDLINE \
        --add-section .linux=${KERNEL_IMAGE} \
            --change-section-vma .linux=$VMA_LINUX \
        --add-section .initrd=${INITRAMFS_FILE} \
            --change-section-vma .initrd=$VMA_INITRD \
        ${EFI_STUB} \
        ${B}/pv-linux.efi

    bbnote "UKI assembled: $(ls -lh ${B}/pv-linux.efi | awk '{print $5}')"
}

# Ensure kernel and initramfs are deployed before we compile.
# The kernel:do_deploy transitively triggers the initramfs multiconfig
# build when INITRAMFS_MULTICONFIG is set in the distro.
do_compile[depends] += "virtual/kernel:do_deploy systemd-boot:do_deploy pantavisor-initramfs:do_image_complete"

do_install() {
    install -d ${D}${datadir}/pv-uki
    install -m 0644 ${B}/pv-linux.efi ${D}${datadir}/pv-uki/pv-linux.efi
    install -m 0644 ${WORKDIR}/cmdline.txt ${D}${datadir}/pv-uki/cmdline.txt
}

do_deploy() {
    install -m 0644 ${B}/pv-linux.efi ${DEPLOYDIR}/pv-linux.efi
    install -m 0644 ${WORKDIR}/cmdline.txt ${DEPLOYDIR}/cmdline.txt
}

addtask deploy after do_compile before do_build

FILES:${PN} = "${datadir}/pv-uki"
