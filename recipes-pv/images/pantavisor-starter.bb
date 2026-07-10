SUMMARY = "Starter Image for Pantavisor"
LICENSE = "MIT"

inherit image pvroot-image pantavisor-docs

FILESPATH = "${@base_set_filespath(["${FILE_DIRNAME}/${BP}", \
        "${FILE_DIRNAME}/${BPN}", "${FILE_DIRNAME}/files"], d)}"

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pvwificonnect pv-avahi pv-avahi-browse"

PVROOT_IMAGE_BSP ?= "core-image-minimal"

do_rootfs[depends] += "virtual/bootloader:do_deploy"

do_rootfs_boot_scr(){
	if [ -f "${DEPLOY_DIR_IMAGE}/boot.scr" ]; then
		mkdir -p ${IMAGE_ROOTFS}/boot
		cp -f ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
	fi
	# boot.scr loads oemEnv.txt from the boot volume root; on UBIFS
	# machines the image rootfs is that volume, so wic IMAGE_BOOT_FILES
	# (pvroot-image.bbclass) never places it there
	if [ -f "${DEPLOY_DIR_IMAGE}/oemEnv.txt" ]; then
		cp -f ${DEPLOY_DIR_IMAGE}/oemEnv.txt ${IMAGE_ROOTFS}/
	fi
}


PVROOTFS_POSTPROCESS_COMMAND = "do_rootfs_boot_scr"
