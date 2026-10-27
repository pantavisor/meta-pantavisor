SUMMARY = "Jetson BSP payload for Pantavisor (modules and NVIDIA firmware)"
LICENSE = "MIT"

inherit core-image

COMPATIBLE_MACHINE = "^jetson-nano-devkit$"
IMAGE_INSTALL = "kernel-modules tegra-firmware"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "tar.gz"
IMAGE_TYPES_MASKED += "pvrexportit"
IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
NO_RECOMMENDATIONS = "1"
