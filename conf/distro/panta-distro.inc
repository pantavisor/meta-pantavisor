require conf/distro/poky.conf

# use custom busybox + mbedtls
BUSYBOX_VERSION_kirkstone = "1.36~pv.%"
BUSYBOX_VERSION_scarthgap = "1.36~pv.%"

PREFERRED_VERSION_busybox = "${@d.getVar("BUSYBOX_VERSION_${DISTRO_CODENAME}", expand=True)}"
PREFERRED_VERSION_mbedtls = "2.28.%"

# mandatory class
IMAGE_CLASSES:append = " image-pvrexport"


PREFERRED_PROVIDER_llvm = "clang"
PREFERRED_PROVIDER_llvm-native = "clang-native"
PREFERRED_PROVIDER_nativesdk-llvm = "nativesdk-clang"
PROVIDES:pn-clang = "llvm"
PROVIDES:pn-clang-native = "llvm-native"
PROVIDES:pn-nativesdk-clang = "nativesdk-llvm"

PREFERRED_PROVIDER_virtual/llvm = "clang"


