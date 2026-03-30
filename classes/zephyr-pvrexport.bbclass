inherit zephyr-sample pvr-ca

DEPENDS += "pvr-native jq-native"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"
PVSTATE = "${WORKDIR}/pvstate"

PSEUDO_IGNORE_PATHS .= ",${PVSTATE},${PVR_CONFIG_DIR}"

# MCU args.json and services.json follow the same naming pattern
# as Linux containers: ${PN}.args.json, ${PN}.services.json or
# args.json, services.json in WORKDIR
PVR_MCU_GROUP ??= "root"

fakeroot do_pvrexport() {
    export PVR_DISABLE_SELF_UPGRADE=1
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"

    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi

    rm -rf ${PVSTATE}
    mkdir -p ${PVSTATE}
    cd ${PVSTATE}
    pvr init

    # find firmware (prefer .elf over .bin -- remoteproc needs ELF)
    # Use DEPLOY_DIR_IMAGE (shared deploy) since DEPLOYDIR (per-recipe
    # staging) may be cleaned by the deploy class before we run.
    fw=""
    if [ -f ${DEPLOY_DIR_IMAGE}/${PN}.elf ]; then
        fw="${DEPLOY_DIR_IMAGE}/${PN}.elf"
    elif [ -f ${DEPLOY_DIR_IMAGE}/${PN}.bin ]; then
        fw="${DEPLOY_DIR_IMAGE}/${PN}.bin"
    else
        bbfatal "No firmware found in DEPLOY_DIR_IMAGE for ${PN}"
    fi

    # build pvr app add args
    args=""
    if [ -f ${WORKDIR}/${PN}.args.json ]; then
        args="--arg-json ${WORKDIR}/${PN}.args.json"
    elif [ -f ${WORKDIR}/args.json ]; then
        args="--arg-json ${WORKDIR}/args.json"
    fi

    pvr app add \
        --force \
        --type image \
        --from "$fw" \
        --group ${PVR_MCU_GROUP} \
        $args \
        ${PN}

    # services.json
    if [ -f ${WORKDIR}/${PN}.services.json ]; then
        cp -f ${WORKDIR}/${PN}.services.json ./${PN}/services.json
    elif [ -f ${WORKDIR}/services.json ]; then
        cp -f ${WORKDIR}/services.json ./${PN}/services.json
    fi

    pvr add
    pvr commit

    # signing (optional -- skip if no keys available)
    if [ -f "${PVR_CONFIG_DIR}/pvs/key.default.pem" ]; then
        pvr sig add --noconfig --part ${PN}
        pvr add
        pvr commit
    fi

    pvr export ${DEPLOY_DIR_IMAGE}/${PN}.pvrexport.tgz
}

do_pvrexport[depends] += "pvr-native:do_populate_sysroot jq-native:do_populate_sysroot squashfs-tools-native:do_populate_sysroot"
do_pvrexport[dirs] += "${PVR_CONFIG_DIR} ${PVSTATE}"
do_pvrexport[cleandirs] += "${PVSTATE}"
addtask pvrexport after do_deploy before do_build
