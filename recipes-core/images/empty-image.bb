
inherit image
IMAGE_FSTYPES = "tar.gz"
PANTAVISOR_MACHINE_FIRMWARE ?= "linux-firmware"
LINGUAS_INSTALL = ""
PACKAGE_INSTALL += "${PANTAVISOR_MACHINE_FIRMWARE}"
IMAGE_INSTALL += ""
IMAGE_FSTYPES:remove = "pvbspit pvrexportit"
IMAGE_TYPES:remove = "pvbspit pvrexportit"

