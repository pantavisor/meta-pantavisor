MACHINE_FEATURES = ""

IMAGE_FSTYPES += "container"

# Don't include kernels in standard images
RDEPENDS_${KERNEL_PACKAGE_NAME}-base = ""

# Use a common kernel recipe for all QEMU machines
PREFERRED_PROVIDER_virtual/kernel ??= "linux-dummy"

EXTRA_IMAGEDEPENDS += ""
