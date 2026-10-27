IMAGE_FSTYPES:jetson-nano-devkit = "ext4 tegraflash"
IMAGE_ROOTFS_SIZE:jetson-nano-devkit = "1048576"
IMAGE_ROOTFS_EXTRA_SPACE:jetson-nano-devkit = "262144"
EXTRA_IMAGECMD:ext4:append:jetson-nano-devkit = " -L root"

# The APP partition holds both /boot and Pantavisor storage. Upstream
# tegraflash packages the QSPI firmware and supplies doflash.sh/dosdcard.sh.
do_rootfs_boot_scr:append:jetson-nano-devkit() {
    test -s ${IMAGE_ROOTFS}/boot/boot.scr || bbfatal "Missing Nano boot script"
}

# Build a whole-card image as well as the recovery bundle. NVIDIA's helper
# can sign and assemble an image file without an attached board or root.
tegraflash_custom_post:append:jetson-nano-devkit() {
    ./dosdcard.sh ${IMGDEPLOYDIR}/${IMAGE_NAME}.sdcard
    gzip -n -c ${IMGDEPLOYDIR}/${IMAGE_NAME}.sdcard > ${IMGDEPLOYDIR}/${IMAGE_NAME}.sdcard.gz
    rm ${IMGDEPLOYDIR}/${IMAGE_NAME}.sdcard
    ln -sf ${IMAGE_NAME}.sdcard.gz ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.sdcard.gz
}
