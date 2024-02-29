
DEPENDS:append = " pvr-native squashfs-tools-native "

IMAGE_TYPES += " pvbspit "
IMAGE_FSTYPES += " pvbspit "
IMAGE_TYPES_MASKED += " ${@bb.utils.contains('IMAGE_BASENAME', 'pantavisor-bsp', 'pvbspit', '', d)}"

inherit image kernel-artifact-names pvr-ca

INITRAMFS_IMAGE_NAME ?= "pantavisor-bsp-${MACHINE}"

PVR_FORMAT_OPTS ?= "-comp xz"

PVBSPSTATE = "${WORKDIR}/pvbspstate"
PVBSP = "${WORKDIR}/pvbsp"
PVBSP_mods = "${WORKDIR}/pvbsp-mods"
PVBSP_fw = "${WORKDIR}/pvbsp-fw"
PVR_PVBSPIT_CONFIG_DIR ?= "${WORKDIR}/pvrpvbspitconfig"

PV_INITIAL_DTB ?= "${UBOOT_DTB_NAME}"

do_image_pvbspit[dirs] = "${TOPDIR} ${PVBSPSTATE} ${PVBSP} ${PVBSP_mods} ${PVBSP_fw} ${PVR_PVBSPIT_CONFIG_DIR} "
do_image_pvbspit[cleandirs] = " ${PVBSPSTATE} "
do_image_pvbspit[depends] += "pantavisor-bsp:do_image_complete virtual/kernel:do_deploy"

PSEUDO_IGNORE_PATHS .= ",${PVBSPSTATE},${PVR_PVBSPIT_CONFIG_DIR}"

fakeroot IMAGE_CMD:pvbspit(){

    export PVR_CONFIG_DIR="${PVR_PVBSPIT_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=true
    if [ -d ${WORKDIR}/pv-developer-ca_generic ]; then
        tar -C ${PVR_PVBSPIT_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_generic/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi
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

    basearts=
    if echo ${KERNEL_IMAGETYPES} | grep -q fitImage > /dev/null; then
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-its-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME} ${PVBSPSTATE}/bsp/pantavisor.its
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME} ${PVBSPSTATE}/bsp/pantavisor.fit
       basearts='"fit": "pantavisor.fit",'
    else 
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
       basearts='
    "linux": "kernel.img",
    "initrd": "pantavisor",'

       if [ -n "${PV_INITIAL_DTB}" ]; then
           cp -f ${DEPLOY_DIR_IMAGE}/${PV_INITIAL_DTB} ${PVBSPSTATE}/bsp/${PV_INITIAL_DTB}
           _pvline="$_pvline
       \"fdt\": \"${PV_INITIAL_DTB}\","
       fi
    fi
          
    _pvline="$basearts"

    cat > ${PVBSPSTATE}/bsp/run.json << EOF
`echo '{'`
    "addons": [],
    "firmware": "firmware.squashfs",
${_pvline}
    "initrd_config": "",
    "modules": "modules.squashfs"
`echo '}'`
EOF
    cat > ${PVBSPSTATE}/bsp/src.json << EOF1
`echo '{}'`
EOF1

    pvr add; pvr commit; pvr checkout -c

    if [ -f "${WORKDIR}/pvs/key.default.pem" ]; then
        export PVR_SIG_KEY="${WORKDIR}/pvs/key.default.pem"
    fi
    if [ -f "${WORKDIR}/pvs/x5c.default.pem" ]; then
        export PVR_X5C_PATH="${WORKDIR}/pvs/x5c.default.pem"
    fi

    pvr sig add --raw bsp --include 'bsp/**' --include '#spec' --exclude 'bsp/src.json'
    pvr add; pvr commit
    pvr sig up
    pvr sig ls
    pvr add; pvr commit
    mkdir -p ${IMGDEPLOYDIR}
    pvr export ${IMGDEPLOYDIR}/bsp-${PN}.pvrexport.tgz
}

addtask rootfs after do_fetch do_unpack

python __anonymous() {
    pn = d.getVar("PN")
    d.delVarFlag("do_unpack", "noexec")
    d.delVarFlag("do_fetch", "noexec")
    d.appendVarFlag('do_image_cmd_pvbsp', 'depends', ' virtual/kernel:do_deploy')
    if not d.getVar("PVROOT_IMAGE_BSP") is None and (d.getVar("PVROOT_IMAGE_BSP") != "") and not pn in d.getVar("PVROOT_IMAGE_BSP") and \
       "linux-dummy" not in d.getVar("PREFERRED_PROVIDER_virtual/kernel"):
        msg = '"PVROOT_IMAGE_BSP" is set and is not this image, but ' \
              'PREFERRED_PROVIDER_virtual/kernel is not "linux-dummy". ' \
              'Setting it to linux-dummy accordingly.'

        d.setVar("PREFERRED_PROVIDER_virtual/kernel", "linux-dummy")
}
