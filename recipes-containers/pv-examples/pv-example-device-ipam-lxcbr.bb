SUMMARY = "Device configuration with a single pvcnet pool on lxcbr0 (10.0.3.0/24)"
DESCRIPTION = "A device.json pvrexport defining one network pool (`pvcnet`) bound to the traditional lxcbr0 bridge / 10.0.3.0/24 subnet. Used by the reservation-walk test which pairs this pool with a legacy-style container that bakes a static IP in the same subnet."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "pvr-native"

inherit pvr-ca

SRC_URI = "file://device-ipam-lxcbr.json"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"
PVSTATE = "${WORKDIR}/pvstate"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    :
}

fakeroot do_create_pvrexport() {
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=1

    if [ -d ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME} ]; then
        mkdir -p ${PVR_CONFIG_DIR}
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz --no-same-owner
    fi

    rm -rf ${PVSTATE}
    mkdir -p ${PVSTATE}
    cd ${PVSTATE}
    pvr init

    cp ${WORKDIR}/device-ipam-lxcbr.json device.json

    pvr add
    pvr commit

    mkdir -p ${DEPLOY_DIR_IMAGE}
    pvr export ${DEPLOY_DIR_IMAGE}/${PN}.pvrexport.tgz
}

addtask create_pvrexport after do_install before do_build
do_create_pvrexport[dirs] = "${TOPDIR} ${PVSTATE} ${PVR_CONFIG_DIR}"
do_create_pvrexport[cleandirs] = "${PVSTATE}"
do_create_pvrexport[depends] = "pvr-native:do_populate_sysroot"

PSEUDO_IGNORE_PATHS .= ",${PVSTATE},${PVR_CONFIG_DIR}"
