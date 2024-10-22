require conf/distro/poky.conf

# use custom busybox + mbedtls
BUSYBOX_VERSION_kirkstone = "1.36~pv.%"
BUSYBOX_VERSION_scarthgap = "1.36~pv.%"

PREFERRED_VERSION_busybox = "${@d.getVar("BUSYBOX_VERSION_${DISTRO_CODENAME}", expand=True)}"
PREFERRED_VERSION_mbedtls = "2.28.%"


