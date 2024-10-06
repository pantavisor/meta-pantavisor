
OVERRIDES =. "mc-${BB_CURRENT_MC}:"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

INITRAMFS_IMAGE ?= "pantavisor-initramfs"

KERNEL_IMAGETYPES:qemumips += "uImage"
KERNEL_CLASSES:qemumips += "kernel-uimage"

KBUILD_DEFCONFIG:qemumips = "malta_defconfig"
KERNEL_DEVICETREE:qemumips = "mti/malta.dtb"

PANTAVISOR_SRC_URI = " \
	file://overlayfs.cfg \
	file://pantavisor.cfg \
	file://pvcrypt.cfg \
	file://dm.cfg \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'file://pantavisor-lz4.cfg', '', d)} \
"


PANTAVISOR_KERNEL_FRAGMENTS = " \
	${WORKDIR}/pantavisor.cfg \
	${WORKDIR}/pvcrypt.cfg \
	${WORKDIR}/overlayfs.cfg \
	${WORKDIR}/dm.cfg \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '${WORKDIR}/pantavisor-lz4.cfg', '', d)} \
"

SRC_URI:append = " \
	${@bb.utils.contains_any('DISTRO_FEATURES', 'pantavisor-system pantavisor-kernel', '${PANTAVISOR_SRC_URI}', '', d)} \
"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${@bb.utils.contains_any('DISTRO_FEATURES', 'pantavisor-system pantavisor-kernel', '${PANTAVISOR_KERNEL_FRAGMENTS}', '', d)} \
"

COMPATIBLE_MACHINE:qemuarm-pv = "qemuarm-pv"


# for bootscript in fitimage
uboot_env:mc-default = "boot"
uboot_env_suffix:mc-default ?= "scr"
uboot_env_src:pvbsp = ""
uboot_env_suffix:pvbsp = ""

UBOOT_ENV = "${uboot_env}"
UBOOT_ENV_SUFFIX = "${uboot_env_suffix}"

