SUMMARY = "A small image just capable of allowing a device to boot."

IMAGE_INSTALL = "busybox ${CORE_IMAGE_EXTRA_INSTALL}"

IMAGE_LINGUAS = " "

LICENSE = "MIT"

FILESPATH = "${@base_set_filespath(["${FILE_DIRNAME}/${BP}", \
        "${FILE_DIRNAME}/${BPN}", "${FILE_DIRNAME}/files"], d)}"

SRC_URI = "file://empty.json"

# PVROOT_CONTAINERS = ""
PVROOT_CONTAINERS_CORE = "connman"
PVROOT_IMAGE_BSP = "fsl-image-network-full-cmdline"
PVROOT_IMAGE = "no"

do_rootfs_boot_scr(){
	if [ -f "${DEPLOY_DIR_IMAGE}/boot.scr" ]; then
		mkdir -p ${IMAGE_ROOTFS}/boot
		cp -f ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
	fi
}


inherit image pvroot-image

PVROOTFS_POSTPROCESS_COMMAND = "do_rootfs_boot_scr;"

