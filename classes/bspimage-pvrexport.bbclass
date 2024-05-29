

DEPENDS:append = " pvr-native \
	squashfs-tools-native \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'lz4-native', '', d)} \
"

IMAGE_TYPES += " pvbspit "
IMAGE_FSTYPES += " pvbspit "


inherit image kernel-artifact-names pvr-ca

IMAGE_TYPES_MASKED += ' ${@oe.utils.conditional("PVROOT_IMAGE_BSP", "${PN}", "wic wic.*", "", d)}'

INITRAMFS_IMAGE_NAME ?= "pantavisor-initramfs-${MACHINE}"
INITRAMFS_DEPLOY_DIR_IMAGE ?= "${DEPLOY_DIR_IMAGE}"
# set some default MULTICONFIG
INITRAMFS_MULTICONFIG ??= ""

UBOOT_DTB_NAME ?= ""

PV_UBOOT_AUTOFDT ?= ""
PVR_FORMAT_OPTS ?= "${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '-comp lz4 -Xhc', '-comp xz', d)}"
PVS_VENDOR_NAME ??= "generic"

PVBSPSTATE = "${WORKDIR}/pvbspstate"
PVBSP = "${WORKDIR}/pvbsp"
PVBSP_mods = "${WORKDIR}/pvbsp-mods"
PVBSP_fw = "${WORKDIR}/pvbsp-fw"
PVR_PVBSPIT_CONFIG_DIR ?= "${WORKDIR}/pvrpvbspitconfig"

# we check for MACHINE_UBOOT_AUTOFDT flag; if not set this machine assumes dtb is same as UBOOT_DTB_NAME
PV_INITIAL_DTB ?= "${@oe.utils.conditional('PV_UBOOT_AUTOFDT', '1', '', '${UBOOT_DTB_NAME}', d)}"

do_image_pvbspit[dirs] = "${TOPDIR} ${PVBSPSTATE} ${PVBSP} ${PVBSP_mods} ${PVBSP_fw} ${PVR_PVBSPIT_CONFIG_DIR} "

do_image_pvbspit[cleandirs] = " ${PVBSPSTATE} "

image_depends = "${@oe.utils.conditional('INITRAMFS_MULTICONFIG', '', 'pantavisor-initramfs:do_image_complete', '', d)} virtual/kernel:do_deploy"
do_image_pvbspit[depends] += "${image_depends}"

image_mcdepends = '${@oe.utils.conditional("INITRAMFS_MULTICONFIG", "", "", "mc::${INITRAMFS_MULTICONFIG}:pantavisor-initramfs:do_image_complete", d) }'
do_image_pvbspit[mcdepends] += '${image_mcdepends}'

PSEUDO_IGNORE_PATHS .= ",${PVBSPSTATE},${PVR_PVBSPIT_CONFIG_DIR}"

fakeroot IMAGE_CMD:pvbspit(){

    export PVR_CONFIG_DIR="${PVR_PVBSPIT_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=true
    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        tar -C ${PVR_PVBSPIT_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
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
    if test -n "${PVBSP_UBOOT_LOGO_BMP}" && test -e "${DEPLOY_DIR_IMAGE}/${PVBSP_UBOOT_LOGO_BMP}"; then
       cp -fL ${DEPLOY_DIR_IMAGE}/${PVBSP_UBOOT_LOGO_BMP} ${PVBSPSTATE}/bsp/uboot-logo.bmp
    fi
    if echo ${KERNEL_IMAGETYPES} | grep -q fitImage > /dev/null; then
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-its-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME} ${PVBSPSTATE}/bsp/pantavisor.its
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME} ${PVBSPSTATE}/bsp/pantavisor.fit
       basearts='"fit": "pantavisor.fit",'
    else 
       kernel_imagetype=${KERNEL_IMAGETYPE}
       if test -n "${KERNEL_ALT_IMAGETYPE}"; then
           kernel_imagetype=${KERNEL_ALT_IMAGETYPE}
       fi
       if test -n "${PVROOT_KERNEL_IMAGETYPE}"; then
           kernel_imagetype=${PVROOT_KERNEL_IMAGETYPE}
       fi
       case ${kernel_imagetype} in
          *.gz)
              gunzip -c ${DEPLOY_DIR_IMAGE}/${kernel_imagetype} > ${PVBSPSTATE}/bsp/kernel.img
              ;;
          vmlinu*)
              echo "COPYING vmlinux type of kernel to bsp: cp -f ${DEPLOY_DIR_IMAGE}/${kernel_imagetype} ${PVBSPSTATE}/bsp/kernel.img"
              cp -f ${DEPLOY_DIR_IMAGE}/${kernel_imagetype} ${PVBSPSTATE}/bsp/kernel.img
              ;;
          *Image)
              cp -f ${DEPLOY_DIR_IMAGE}/${kernel_imagetype} ${PVBSPSTATE}/bsp/kernel.img
              ;;
          *)
              echo "Unknown kernel type: ${kernel_imagetype}"
              exit 1
       esac
       for imagetype in ${INITRAMFS_FSTYPES}; do
           if cp ${INITRAMFS_DEPLOY_DIR_IMAGE}/pantavisor-initramfs-${MACHINE}.${imagetype} ${PVBSPSTATE}/bsp/pantavisor; then
               break
           fi
       done
       if ! [ -f ${PVBSPSTATE}/bsp/pantavisor ]; then
           echo "ERROR: no pantavisor initramfs found for types ${INITRAMFS_FSTYPES}"
           exit 2
       fi
       basearts='
    "linux": "kernel.img",
    "initrd": "pantavisor",'

       if [ -n "${PV_INITIAL_DTB}" ]; then
           cp -f ${DEPLOY_DIR_IMAGE}/${PV_INITIAL_DTB} ${PVBSPSTATE}/bsp/${PV_INITIAL_DTB}
           basearts="$basearts
       \"fdt\": \"${PV_INITIAL_DTB}\","
       fi
       if [ -n "${PV_UBOOT_AUTOFDT}" -a -n "${KERNEL_DEVICETREE}" ]; then
           for dtb in ${KERNEL_DEVICETREE}; do
               dtb_file=`basename $dtb`
               cp -f ${DEPLOY_DIR_IMAGE}/$dtb_file ${PVBSPSTATE}/bsp/
           done
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

    pvr sig add --raw bsp --include device.json --include 'bsp/**' --include '#spec' --exclude 'bsp/src.json'
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
