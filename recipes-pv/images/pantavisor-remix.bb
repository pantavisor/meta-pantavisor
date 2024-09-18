SUMMARY = "A small image just capable of allowing a device to boot."
LICENSE = "MIT"

inherit image pvroot-image

FILESPATH = "${@base_set_filespath(["${FILE_DIRNAME}/${BP}", \
        "${FILE_DIRNAME}/${BPN}", "${FILE_DIRNAME}/files"], d)}"

IMAGE_INSTALL = ""
IMAGE_LINGUAS = ""
IMAGE_TYPES_MASKED += " pvbspit pvrexportit"

SRC_URI = "file://device.json"

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
