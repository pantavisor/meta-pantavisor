
DEPENDS:append = " pvr-native squashfs-tools-native "

inherit image

IMAGE_TYPES += " pvrexportit "
IMAGE_FSTYPES += " pvrexportit "
IMAGE_TYPES_MASKED += " ${@bb.utils.contains('PVROOT_IMAGE', 'no', 'pvrexportit', '', d)} ${@bb.utils.contains('IMAGE_BASENAME', 'pantavisor-bsp', ' pvrexportit ', '', d)} "


PVR_FORMAT_OPTS ?= "-comp xz"
PVR_SOMETHING = "yes"

PVSTATE = "${WORKDIR}/pvstate"

do_image_pvrexportit[dirs] = " ${TOPDIR} ${PVSTATE} "
do_image_pvrexportit[cleandirs] = " "

fakeroot IMAGE_CMD:pvrexportit(){

    echo Ja2: ${D} asa
    cd ${PVSTATE}
    pvr init
    pvr app add \
	--force \
    	--type rootfs \
	--from "${IMAGE_ROOTFS}" \
	--format-options="${PVR_FORMAT_OPTS} -e lib/modules -e lib/firmware " \
	${PN}
    pvr add
    pvr commit
    mkdir -p ${IMGDEPLOYDIR}/${DISTRO}/
    pvr export ${IMGDEPLOYDIR}/${DISTRO}/${PN}.pvrexport.tgz
}


python __anonymous() {
    pn = d.getVar("PN")
    if not d.getVar("PVROOT_IMAGE_BSP") is None and not pn in d.getVar("PVROOT_IMAGE_BSP") and \
       "linux-dummy" not in d.getVar("PREFERRED_PROVIDER_virtual/kernel"):
        msg = '"PVROOT_IMAGE_BSP" is set and not this image, but ' \
              'PREFERRED_PROVIDER_virtual/kernel is not "linux-dummy". ' \
              'Setting it to linux-dummy accordingly.'

        d.setVar("PREFERRED_PROVIDER_virtual/kernel", "linux-dummy")
}

