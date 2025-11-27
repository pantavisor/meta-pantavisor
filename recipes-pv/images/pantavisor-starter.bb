SUMMARY = "Starter Image for Pantavisor"
LICENSE = "MIT"

inherit image pvroot-image

FILESPATH = "${@base_set_filespath(["${FILE_DIRNAME}/${BP}", \
        "${FILE_DIRNAME}/${BPN}", "${FILE_DIRNAME}/files"], d)}"

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk pv-alpine-connman pv-pvwificonnect"

PVROOT_CONTAINERS_CORE ?= "pv-pvr-sdk"
PVROOT_IMAGE_BSP ?= "core-image-minimal"


do_rootfs[depends] += "virtual/bootloader:do_deploy"

do_rootfs_boot_scr(){
	if [ -f "${DEPLOY_DIR_IMAGE}/boot.scr" ]; then
		mkdir -p ${IMAGE_ROOTFS}/boot
		cp -f ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
	fi
}

PVROOTFS_POSTPROCESS_COMMAND = "do_rootfs_boot_scr;"
