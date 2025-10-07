
inherit core-image image-oci oci2docker

DOCKER_IMAGE_NAME ?= "pantavisor-dockerimage"
DOCKER_IMAGE_TAG ?= "latest"

IMAGE_CLASSES:remove = "image-pvrexport"
IMAGE_FSTYPES = "container oci"
IMAGE_FSTYPES:remove = "pvbspit pvrexportit"
#IMAGE_TYPES:remove = "pvbspit pvrexportit"
#IMAGE_TYPES:append = "oci"

python __anonymous() {
    pn = d.getVar("PN")
    d.delVarFlag("do_unpack", "noexec")
    d.delVarFlag("do_fetch", "noexec")
}

addtask rootfs after do_fetch do_unpack
