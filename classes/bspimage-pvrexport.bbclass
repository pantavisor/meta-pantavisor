
DEPENDS:append = " pvr-native squashfs-tools-native "

IMAGE_TYPES += " pvbspit "
IMAGE_FSTYPES += " pvbspit "
IMAGE_TYPES_MASKED += " ${@bb.utils.contains('IMAGE_BASENAME', 'pantavisor-bsp', 'pvbspit', '', d)}"

inherit image

PVR_FORMAT_OPTS ?= "-comp xz"

PVBSPSTATE = "${WORKDIR}/pvbspstate"
PVBSP = "${WORKDIR}/pvbsp"
PVBSP_mods = "${WORKDIR}/pvbsp-mods"
PVBSP_fw = "${WORKDIR}/pvbsp-fw"
PVR_CONFIG_DIR ?= "${WORKDIR}/pvbspconfig"

do_image_pvbspit[dirs] = "${TOPDIR} ${PVBSPSTATE} ${PVBSP} ${PVBSP_mods} ${PVBSP_fw} ${PVR_CONFIG_DIR} "
do_image_pvbspit[cleandirs] = " "
do_image_pvbspit[depends] += "pantavisor-bsp:do_image_complete"

fakeroot IMAGE_CMD:pvbspit(){

    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    cd ${PVBSP}
    mkdir -p ${PVBSP_mods}/lib/modules
    [ -d ${IMAGE_ROOTFS}/lib/modules/ ] && cp -rf ${IMAGE_ROOTFS}/lib/modules/*/* ${PVBSP_mods}
    [ -d ${IMAGE_ROOTFS}/lib/firmware/ ] && cp -rf ${IMAGE_ROOTFS}/lib/firmware/* ${PVBSP_fw}
    cd ${PVBSPSTATE}
    pvr init
    [ -d bsp ] || mkdir bsp
    [ -f bsp/modules.squashfs ] && rm -f bsp/modules.squashfs
    [ -f bsp/firmware.squashfs ] && rm -f bsp/firmware.squashfs

    mksquashfs ${PVBSP_mods} ${PVBSPSTATE}/bsp/modules.squashfs ${PVR_FORMAT_OPTS}
    mksquashfs ${PVBSP_fw} ${PVBSPSTATE}/bsp/firmware.squashfs ${PVR_FORMAT_OPTS}
    err=0

    case ${KERNEL_IMAGETYPE} in
       *.gz)
           gunzip -c ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} > ${PVBSPSTATE}/bsp/kernel.img
           ;;
       Image)
           cp -f ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} ${PVBSPSTATE}/bsp/kernel.img
           ;;
       *)
           echo "Unknown kernel type: ${KERNEL_IMAGETYPE}"
           exit 1
    esac
          
    cp -f ${DEPLOY_DIR_IMAGE}/pantavisor-bsp-${MACHINE}.cpio.gz ${PVBSPSTATE}/bsp/pantavisor

    _pvline='    "initrd": "pantavisor",
    "linux": "kernel.img",'

    if [ -n "${PV_INITIAL_DTB}" ]; then
        cp -f ${DEPLOY_DIR_IMAGE}/${PV_INITIAL_DTB} ${PVBSPSTATE}/bsp/${PV_INITIAL_DTB}
        _pvline="$_pvline
    \"fdt\": \"${PV_INITIAL_DTB}\","
    fi

    cat > ${PVBSPSTATE}/bsp/run.json << EOF
`echo '{'`
    "addons": [],
    "firmware": "firmware.squashfs",
${_pvline}
    "initrd_config": "",
    "modules": "modules.squashfs"
`echo '}'`
EOF
    pvr add; pvr commit
    mkdir -p ${IMGDEPLOYDIR}/${DISTRO}
    pvr export ${IMGDEPLOYDIR}/${DISTRO}/bsp-${PN}.pvrexport.tgz
}


python __anonymous() {
    pn = d.getVar("PN")
    d.appendVarFlag('do_image_cmd_pvbsp', 'depends', ' virtual/kernel:do_deploy')
    if not d.getVar("PVROOT_IMAGE_BSP") is None and (d.getVar("PVROOT_IMAGE_BSP") != "") and not pn in d.getVar("PVROOT_IMAGE_BSP") and \
       "linux-dummy" not in d.getVar("PREFERRED_PROVIDER_virtual/kernel"):
        msg = '"PVROOT_IMAGE_BSP" is set and is not this image, but ' \
              'PREFERRED_PROVIDER_virtual/kernel is not "linux-dummy". ' \
              'Setting it to linux-dummy accordingly.'

        d.setVar("PREFERRED_PROVIDER_virtual/kernel", "linux-dummy")
}
