# Simple initramfs image artifact generation for tiny images.
DESCRIPTION = "Pantavisor enabled Initramfs image for Pantavisor BSPs"

VIRTUAL-RUNTIME_dev_manager ?= "busybox-mdev"

VIRTUAL-RUNTIME_init_manager = "pantavisor"

PACKAGE_INSTALL = "pantavisor dropbear-pv busybox base-passwd kmod ${ROOTFS_BOOTSTRAP_INSTALL}"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""

IMAGE_BASENAME = "pantavisor-bsp"
IMAGE_NAME_SUFFIX ?= ""
IMAGE_LINGUAS = ""

LICENSE = "MIT"

# don't actually generate an image, just the artifacts needed for one
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"

inherit core-image

IMAGE_FSTYPES:remove = "pvbspit"
IMAGE_TYPES:remove = "pvbspit"

#TCLIBC = "musl"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Use the same restriction as initramfs-live-install
COMPATIBLE_HOST = "(i.86|x86_64|aarch64|arm|mips|riscv).*-linux"

ROOTFS_POSTINSTALL_COMMAND += "do_init_symlink"

do_init_symlink() {
	ln -sfr ${IMAGE_ROOTFS}/usr/bin/pantavisor ${IMAGE_ROOTFS}/sbin/init
}


