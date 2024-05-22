# Simple initramfs image artifact generation for tiny images.
DESCRIPTION = "Pantavisor enabled Initramfs image for Pantavisor BSPs"

VIRTUAL-RUNTIME_dev_manager ?= "busybox-mdev"

VIRTUAL-RUNTIME_init_manager = "pantavisor"

PACKAGE_INSTALL = "pantavisor dropbear-pv busybox base-passwd kmod ${ROOTFS_BOOTSTRAP_INSTALL}"

IMAGE_TYPES_MASKED += " pvbspit pvrexportit"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""
AGL_FEATURES = ""

IMAGE_BASENAME = "pantavisor-initramfs"
IMAGE_NAME_SUFFIX ?= ""
IMAGE_LINGUAS = ""

LICENSE = "MIT"

# don't actually generate an image, just the artifacts needed for one
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"

DEPENDS:append = " pvr-native \
	squashfs-tools-native \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'lz4-native', '', d)} \
"

inherit image

EXTRA_IMAGEDEPENDS = ""
UBOOT_ENV = ""
KERNEL_DEPLOY_DEPEND = ""

IMAGE_FSTYPES:remove = "pvbspit pvrexportit"
IMAGE_TYPES:remove = "pvbspit pvrexportit"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Use the same restriction as initramfs-live-install
COMPATIBLE_HOST = "(i.86|x86_64|aarch64|arm|mips|riscv).*-linux"

ROOTFS_POSTINSTALL_COMMAND += "do_init_symlink"

do_init_symlink() {
	ln -sfr ${IMAGE_ROOTFS}/usr/bin/pantavisor ${IMAGE_ROOTFS}/sbin/init
}

