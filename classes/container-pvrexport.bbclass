DEPENDS:append = " pvr-native \
	squashfs-tools-native \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'lz4-native', '', d)} \
"

IMAGE_TYPES += " pvrexportit "
IMAGE_FSTYPES:append = " pvrexportit "

inherit pvr-ca

python __anonymous() {
    pn = d.getVar("PN")
    d.delVarFlag("do_unpack", "noexec")
    d.delVarFlag("do_fetch", "noexec")

    if not bb.data.inherits_class('image', d):
        return

    # Add image-specific logic
    d.appendVar("IMAGE_INSTALL", " pvcontrol")
    d.setVarFlag("do_image_pvrexportit", "dirs", " ${TOPDIR} ${PVSTATE} ${PVR_CONFIG_DIR} ")
    d.setVarFlag("do_image_pvrexportit", "cleandirs", " ${PVSTATE} ")
}

PVR_FORMAT_OPTS ?= "${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '-comp lz4 -Xhc', '-comp xz', d)}"

PVSTATE = "${WORKDIR}/pvstate"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"

PVR_APP_ADD_EXTRA_ARGS ??= "  --volume ovl:/var:permanent"
PVR_APP_ADD_GROUP ??= "root"

PVRIMAGE_AUTO_MDEV ??= "1"

# Define a config overlay directory that the image recipe will make available
# in ${WORKDIR} before the IMAGE_CMD task for ${PN} container.
# This directory will be added to the pvrexport as _config/${PN}
PV_CONFIG_OVERLAY_DIR ??= ""

PSEUDO_IGNORE_PATHS .= ",${PVSTATE},${PVR_CONFIG_DIR}"

fakeroot IMAGE_CMD:pvrexportit(){

    which pvr
    pvr --version
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=1
    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi
    cd ${PVSTATE}
    pvr init
    if [ -f ${WORKDIR}/${PN}.args.json ]; then
        args="--arg-json ${WORKDIR}/${PN}.args.json "
    elif [ -f ${WORKDIR}/args.json ]; then
        args="--arg-json ${WORKDIR}/args.json "
    fi
    if [ -f ${WORKDIR}/${PN}.config.json ]; then
        args="$args --config-json ${WORKDIR}/${PN}.config.json "
    elif [ -f ${WORKDIR}/config.json ]; then
        args="$args --config-json ${WORKDIR}/config.json "
    fi
    pvr app add \
        --force \
        --type rootfs \
        --from "${IMAGE_ROOTFS}" \
        --group ${PVR_APP_ADD_GROUP} \
        $args ${PVR_APP_ADD_EXTRA_ARGS} \
        --format-options="${PVR_FORMAT_OPTS} -e lib/modules -e lib/firmware " \
        ${PN}
    pvr add
    pvr commit
    if [ -f ${WORKDIR}/${PN}.mdev.json ]; then
        cp -f ${WORKDIR}/${PN}.mdev.json ./${PN}/mdev.json
    elif [ "${PVRIMAGE_AUTO_MDEV}" = "1" ]; then
       cat > ${PN}/mdev.json << EOF1
{
    "rules": [
        ".* 0:0 666"
    ]
 }
EOF1
    fi
    if [ -f ${WORKDIR}/${PN}.services.json ]; then
        cp -f ${WORKDIR}/${PN}.services.json ./${PN}/services.json
    elif [ -f ${WORKDIR}/services.json ]; then
        cp -f ${WORKDIR}/services.json ./${PN}/services.json
    fi
    if [ -n "${PV_CONFIG_OVERLAY_DIR}" ]; then
        mkdir -p _config
        cp -rf ${WORKDIR}/${PV_CONFIG_OVERLAY_DIR} _config/${PN}
    fi
    pvr add
    pvr commit
    pvr sig add --noconfig --part ${PN}
    pvr add
    pvr commit
    mkdir -p ${IMGDEPLOYDIR}/
    pvr export ${IMGDEPLOYDIR}/${PN}.pvrexport.tgz
}

addtask rootfs after do_fetch do_unpack
