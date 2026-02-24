# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Device configuration (hybrid)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "pvr-native jq-native"

inherit deploy pvr-ca

PVS_URI = "https://gitlab.com/pantacor/pv-developer-ca/-/archive/2340d747c4acd0a1a702b3d7d5acc014b51daaa7/pv-developer-ca-master.tar.gz;striplevel=1"
PVS_URI_SHA256 = "9f4c55dad2c121a4ca2ae39e2767eb4a214822ee34041a65692766ae438f96d8"

SRC_URI = "file://device.json.ingress-hybrid \
           ${PVS_URI};name=pv-developer-ca;subdir=pv-developer-ca_generic \
          "
SRC_URI[pv-developer-ca.sha256sum] = "${PVS_URI_SHA256}"

PVR_CONFIG_DIR = "${WORKDIR}/pvrconfig"
PVR_HOME_DIR = "${WORKDIR}/home"

do_compile[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_compile() {
    export PVR_DISABLE_SELF_UPGRADE=true
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export HOME="${PVR_HOME_DIR}"

    mkdir -p ${PVR_CONFIG_DIR}
    if [ -d ${WORKDIR}/pv-developer-ca_generic ]; then
        tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_generic/pvs/pvs.defaultkeys.tar.gz
    fi
    if [ -f "${PVR_CONFIG_DIR}/key.default.pem" ]; then
        export PVR_SIG_KEY="${PVR_CONFIG_DIR}/key.default.pem"
    fi
    if [ -f "${PVR_CONFIG_DIR}/x5c.default.pem" ]; then
        export PVR_X5C_PATH="${PVR_CONFIG_DIR}/x5c.default.pem"
    fi

    cd ${B}/pvrrepo
    pvr init
    cp -f ${WORKDIR}/device.json.ingress-hybrid device.json
    pvr add
    pvr commit
    pvr sig add -n --raw device-config --include "device.json"
    pvr add
    pvr commit
    pvr sig up
    pvr commit
}

do_deploy[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_deploy() {
    export PVR_DISABLE_SELF_UPGRADE=true
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export HOME="${PVR_HOME_DIR}"

    cd ${B}/pvrrepo
    pvr export ${DEPLOYDIR}/${PN}.pvrexport.tgz
}

addtask deploy after do_compile
