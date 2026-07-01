
# you dont need to use this distro, but remember to set these
DISTRO_FEATURES += "pantavisor-appengine"
PANTAVISOR_FEATURES:append = " appengine"
PANTAVISOR_FEATURES:append = " pv-manifest-audit"
PANTAVISOR_FEATURES:remove = "autogrow"

PREFERRED_VERSION_mbedtls = "2.28.%"

PANTAVISOR_MACHINE_FIRMWARE ?= ""
PANTAVISOR_MACHINE_KERNEL_MODULES ?= ""

# appengine builds sign pvrexport parts with the vendor developer CA
PVREXPORT_VENDOR_NAME ?= "${PVS_VENDOR_NAME}"


