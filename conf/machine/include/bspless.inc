MACHINE_FEATURES = ""

IMAGE_FSTYPES += "container tar.bz2"

# Don't include kernels in standard images
RDEPENDS_${KERNEL_PACKAGE_NAME}-base = ""

# Use a common kernel recipe for all QEMU machines
PREFERRED_PROVIDER_virtual/kernel ??= "linux-dummy"

EXTRA_IMAGEDEPENDS += ""

# Example: Disable graphical interface
DISTRO_FEATURES:remove = "x11 wayland"

# Example: Keep it minimal
DISTRO_FEATURES:remove = "opengl alsa"

PACKAGE_EXCLUDE_KERNEL = "1"
