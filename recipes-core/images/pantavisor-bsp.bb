# Simple initramfs image artifact generation for tiny images.
DESCRIPTION = "Pantavisor enabled Initramfs image for Pantavisor BSPs"

VIRTUAL-RUNTIME_dev_manager ?= "busybox-mdev"

PACKAGE_INSTALL = "pantavisor packagegroup-core-boot dropbear-pv ${VIRTUAL-RUNTIME_base-utils} ${VIRTUAL-RUNTIME_dev_manager} base-passwd ${ROOTFS_BOOTSTRAP_INSTALL}"

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

TCLIBC = "musl"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# Use the same restriction as initramfs-live-install
COMPATIBLE_HOST = "(i.86|x86_64|aarch64|arm|mips|riscv).*-linux"

python tinyinitrd () {
  # Modify our init file so the user knows we drop to shell prompt on purpose
  newinit = None
  with open(d.expand('${IMAGE_ROOTFS}/init'), 'r') as init:
    newinit = init.read()
    newinit = newinit.replace('Cannot find $ROOT_IMAGE file in /run/media/* , dropping to a shell ', 'Poky Tiny Reference Distribution:')
  with open(d.expand('${IMAGE_ROOTFS}/init'), 'w') as init:
    init.write(newinit)
}

#IMAGE_PREPROCESS_COMMAND += "tinyinitrd;"

QB_KERNEL_CMDLINE_APPEND += " init=/usr/bin/pantavisor "

