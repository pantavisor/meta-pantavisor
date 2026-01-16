SUMMARY = "Boot selector partition for RPi tryboot A/B"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image

IMAGE_CLASSES:remove = "sdcard_image-rpi"

IMAGE_FSTYPES = "vfat"
IMAGE_ROOTFS_SIZE = "16384"
IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
EXTRA_IMAGECMD:vfat = "-F 16 -S 512 -n BOOTSEL"

IMAGE_INSTALL = ""
PACKAGE_INSTALL = ""
IMAGE_LINGUAS = ""

do_rootfs[recrdeptask] = ""
do_rootfs[depends] += "rpi-bootfiles:do_deploy"

do_rootfs() {
    rm -rf ${IMAGE_ROOTFS}
    mkdir -p ${IMAGE_ROOTFS}

    # Empty config.txt required for valid boot source
    touch ${IMAGE_ROOTFS}/config.txt

    # autoboot.txt for tryboot A/B
    cat > ${IMAGE_ROOTFS}/autoboot.txt << 'EOF'
[all]
tryboot_a_b=1
boot_partition=2

[tryboot]
boot_partition=3
EOF

    # bootcode.bin for Pi 0/1/2/3 (Pi 4/5 have it in EEPROM but it's harmless)
    if [ -e "${DEPLOY_DIR_IMAGE}/${BOOTFILES_DIR_NAME}/bootcode.bin" ]; then
        install -m 0644 "${DEPLOY_DIR_IMAGE}/${BOOTFILES_DIR_NAME}/bootcode.bin" ${IMAGE_ROOTFS}/
    fi
}

create_wks_symlink() {
    ln -sf ${IMAGE_NAME}.rootfs.vfat ${DEPLOY_DIR_IMAGE}/rpi-bootsel.vfat
}

do_image_complete[postfuncs] += "create_wks_symlink"


