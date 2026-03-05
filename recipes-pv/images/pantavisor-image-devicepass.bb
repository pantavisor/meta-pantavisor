SUMMARY = "Pantavisor DevicePass Image"
DESCRIPTION = "Device image with blockchain-native identity: \
devicepass container, hub, anvil testnet, and IPAM networking."
LICENSE = "MIT"

inherit image pvroot-image

PVROOT_CONTAINERS_CORE = " \
    pv-devicepass-container \
    pv-devicepass-hub \
    pv-devicepass-anvil \
    pv-example-device-config-proxy \
"

PVROOT_IMAGE_BSP ?= "core-image-minimal"

do_rootfs[depends] += "virtual/bootloader:do_deploy"

do_rootfs_boot_scr() {
	if [ -f "${DEPLOY_DIR_IMAGE}/boot.scr" ]; then
		mkdir -p ${IMAGE_ROOTFS}/boot
		cp -f ${DEPLOY_DIR_IMAGE}/boot.scr ${IMAGE_ROOTFS}/boot/
	fi
}

PVROOTFS_POSTPROCESS_COMMAND = "do_rootfs_boot_scr;"
