
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

DEPENDS:append = " pvr-native squashfs-tools-native "

IMAGE_TYPES += " pvrexportit "
IMAGE_FSTYPES += " pvrexportit "
IMAGE_TYPES_MASKED += " ${@bb.utils.contains('PVROOT_IMAGE', 'no', 'pvrexportit', '', d)} ${@bb.utils.contains('IMAGE_BASENAME', 'pantavisor-bsp', ' pvrexportit ', '', d)} "

inherit image pvr-ca

IMAGE_INSTALL += "pvcontrol"

PVR_FORMAT_OPTS ?= "-comp xz"
PVR_SOMETHING = "yes"

PVSTATE = "${WORKDIR}/pvstate"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"

do_image_pvrexportit[dirs] = " ${TOPDIR} ${PVSTATE} ${PVR_CONFIG_DIR} "
do_image_pvrexportit[cleandirs] = " ${PVSTATE} "

PSEUDO_IGNORE_PATHS .= ",${PVSTATE},${PVR_CONFIG_DIR}"

fakeroot IMAGE_CMD:pvrexportit(){

    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    if [ -d ${WORKDIR}/pv-developer-ca_generic ]; then
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_generic/pvs/pvs.defaultkeys.tar.gz --no-same-owner
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
	$args \
	--format-options="${PVR_FORMAT_OPTS} -e lib/modules -e lib/firmware " \
	${PN}
    pvr add
    pvr commit
    if [ -f ${WORKDIR}/${PN}.mdev.json ]; then
        cp -f ${WORKDIR}/${PN}.mdev.json ./${PN}/mdev.json
    else
       cat > ${PN}/mdev.json << EOF1
{
    "rules": [
        ".* 0:0 666"
    ]
 }
EOF1
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

python __anonymous() {
    pn = d.getVar("PN")
    d.delVarFlag("do_unpack", "noexec")
    d.delVarFlag("do_fetch", "noexec")
    if not d.getVar("PVROOT_IMAGE_BSP") is None and not pn in d.getVar("PVROOT_IMAGE_BSP") and \
       "linux-dummy" not in d.getVar("PREFERRED_PROVIDER_virtual/kernel"):
        msg = '"PVROOT_IMAGE_BSP" is set and not this image, but ' \
              'PREFERRED_PROVIDER_virtual/kernel is not "linux-dummy". ' \
              'Setting it to linux-dummy accordingly.'

        d.setVar("PREFERRED_PROVIDER_virtual/kernel", "linux-dummy")
}

