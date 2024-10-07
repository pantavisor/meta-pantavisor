LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit deploy kernel-artifact-names pvr-ca image-artifact-names

DEPENDS:append = " \
	pvr-native \
	squashfs-tools-native \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'lz4-native', '', d)} \
"

INITRAMFS_IMAGE ?= "pantavisor-initramfs"
INITRAMFS_IMAGE_NAME ?= "${@['${INITRAMFS_IMAGE}-${MACHINE}', ''][d.getVar('INITRAMFS_IMAGE') == '']}"
INITRAMFS_MULTICONFIG ?= ""
INITRAMFS_DEPLOY_DIR_IMAGE = '${@oe.utils.conditional("INITRAMFS_MULTICONFIG", "", "${DEPLOY_DIR_IMAGE}", "${TOPDIR}/tmp-${DISTRO_CODENAME}-${INITRAMFS_MULTICONFIG}/deploy/images/${MACHINE}", d)}'

OVERRIDES =. "${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'pv-squash-lz4:', '', d)}"
OVERRIDES =. "${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-zstd', 'pv-squash-zstd:', '', d)}"

PVR_FORMAT_OPTS:pv-squash-lz4 ?= "-comp lz4 -Xhc"
PVR_FORMAT_OPTS:pv-squash-zstd ?= "-comp zstd"
PVR_FORMAT_OPTS ?= "-comp xz"

PVS_VENDOR_NAME ??= "generic"
PV_INITIAL_DTB ?= "${UBOOT_DTB_NAME}"
PSEUDO_IGNORE_PATHS .= ",${PVBSPSTATE},${PVR_PVBSPIT_CONFIG_DIR}"

PVBSPSTATE = "${WORKDIR}/pvbspstate"
PVBSP = "${WORKDIR}/pvbsp"
PVBSP_mods = "${WORKDIR}/pvbsp-mods"
PVBSP_fw = "${WORKDIR}/pvbsp-fw"
PVR_PVBSPIT_CONFIG_DIR ?= "${WORKDIR}/pvrpvbspitconfig"

do_compile[dirs] = "${TOPDIR} ${PVBSPSTATE} ${PVBSP} ${PVBSP_mods} ${PVBSP_fw} ${PVR_PVBSPIT_CONFIG_DIR} "
do_compile[cleandirs] = " ${PVBSPSTATE} ${PVBSP_mods} ${PVBSP_fw}"

VIRTUAL-RUNTIME_pantavisor_skel ??= "pantavisor-default-skel"

PVROOT_IMAGE_BSP ?= "empty-image"

compile_depends = ' \
	${@oe.utils.conditional("INITRAMFS_MULTICONFIG", "", "${INITRAMFS_IMAGE}:do_image_complete", "", d)} \
	${PVROOT_IMAGE_BSP}:do_image_complete \
	${VIRTUAL-RUNTIME_pantavisor_skel}:do_deploy \
	virtual/kernel:do_deploy \
	'
do_compile[depends] += "${compile_depends}"

compile_mcdepends = '\
	${@oe.utils.conditional("INITRAMFS_MULTICONFIG", "", "", "mc::${INITRAMFS_MULTICONFIG}:${INITRAMFS_IMAGE}:do_image_complete", d)} \
	'
do_compile[mcdepends] += '${compile_mcdepends}'

fakeroot do_compile(){

    set -x
    export TMPDIR=${WORKDIR}/tmp
    mkdir -p $TMPDIR
    export PVR_CONFIG_DIR="${PVR_PVBSPIT_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=true
    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        tar -C ${PVR_PVBSPIT_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi
    cd ${PVBSP}

    # make up proto_image_name by using IMAGE_LINK_NAME and replacing the ${PN}
    # prefix with proto image (PVROOT_IMAGE_BSP or empty-image)
    proto_image_name="${IMAGE_LINK_NAME}"
    pn="${PN}"
    proto_image_name=${PVROOT_IMAGE_BSP}-"${proto_image_name#$pn-}"
    fstype="tar.gz"
    mkdir -p ${PVBSP_mods}/lib/modules
    tar -C ${PVBSP_mods} -xvf ${DEPLOY_DIR_IMAGE}/${proto_image_name}.${fstype} --strip-components=4 ./lib/modules || true
    mkdir -p ${PVBSP_mods}/lib/firmware
    tar -C ${PVBSP_fw} -xvf ${DEPLOY_DIR_IMAGE}/${proto_image_name}.${fstype} --strip-components=3 ./lib/firmware || true
    cd ${PVBSPSTATE}
    pvr init
    pvr get ${DEPLOY_DIR_IMAGE}/${VIRTUAL-RUNTIME_pantavisor_skel}.pvrexport.tgz
    pvr checkout
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
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-its-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME}${PV_FIT_ITS_SUFFIX} ${PVBSPSTATE}/bsp/pantavisor.its
       cp -fL ${DEPLOY_DIR_IMAGE}/fitImage-${INITRAMFS_IMAGE_NAME}-${KERNEL_FIT_LINK_NAME}${PV_FIT_NAME_SUFFIX} ${PVBSPSTATE}/bsp/pantavisor.fit
       basearts='"fit": "pantavisor.fit",'
    else 
       case ${KERNEL_IMAGETYPE} in
          *.gz)
              gunzip -c ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} > ${PVBSPSTATE}/bsp/kernel.img
              ;;
          *Image)
              cp -f ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} ${PVBSPSTATE}/bsp/kernel.img
              ;;
          vmlinu*)
              cp -f ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} ${PVBSPSTATE}/bsp/kernel.img
              ;;

          *)
              echo "Unknown kernel type: ${KERNEL_IMAGETYPE}"
              exit 1
       esac
       cp -f ${INITRAMFS_DEPLOY_DIR_IMAGE}/${INITRAMFS_IMAGE_NAME}.cpio.gz ${PVBSPSTATE}/bsp/pantavisor
       basearts='
    "linux": "kernel.img",
    "initrd": "pantavisor",'

       if [ -n "${PV_INITIAL_DTB}" ]; then
           cp -f ${DEPLOY_DIR_IMAGE}/${PV_INITIAL_DTB} ${PVBSPSTATE}/bsp/${PV_INITIAL_DTB}
           _pvline="$_pvline
       \"fdt\": \"${PV_INITIAL_DTB}\","
       fi
       if [ -n "${PV_UBOOT_AUTOFDT}" -a -n "${KERNEL_DEVICETREE}" ]; then
           for dtb in ${KERNEL_DEVICETREE}; do
               dtb_file=`basename $dtb`
               if [ -n "${PV_UBOOT_FLATFDT}" ]; then
                   dtb=""
               fi
               install -D -m 0644 ${DEPLOY_DIR_IMAGE}/$dtb_file ${PVBSPSTATE}/bsp/$dtb
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

    if [ "${UBOOT_SIGN_ENABLE}" = "1" -a -f "bsp/pantavisor.fit" ]; then
        pvr_extra_sig_args="--exclude bsp/pantavisor.fit"
    fi

    pvr sig add --raw bsp \
	--include 'bsp/**' \
	--include 'device.json' \
	--include '#spec' \
	--exclude 'bsp/src.json' \
	${pvr_extra_sig_args}

    pvr add; pvr commit
    pvr sig up
    pvr sig ls
    pvr add; pvr commit
    mkdir -p ${DEPLOY_DIR_IMAGE}
    pvr export ${DEPLOY_DIR_IMAGE}/${PN}-${MACHINE}.pvrexport.tgz

    # export pvs
    rm -rf ${DEPLOY_DIR_IMAGE}/${PN}-pvs
    cp -rf ${PVR_PVBSPIT_CONFIG_DIR}/pvs ${DEPLOY_DIR_IMAGE}/${PN}-pvs
}

