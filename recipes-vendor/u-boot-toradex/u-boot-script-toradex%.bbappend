do_mkimage() {
    sed -e 's/@@KERNEL_BOOTCMD@@/${KERNEL_BOOTCMD}/' \
        -e 's/@@KERNEL_IMAGETYPE@@/${KERNEL_IMAGETYPE}/' \
        "${WORKDIR}/boot.cmd.pvgeneric" > ${B}/boot.cmd
    mkimage -T script -C none -n "Distro boot script Panvaisor" -d ${B}/boot.cmd ${B}/boot.scr
}

