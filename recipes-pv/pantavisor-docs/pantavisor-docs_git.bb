SUMMARY = "meta-pantavisor documentation tarball"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit nopackages deploy

DEPENDS += "jq-native"

# docs/ lives at the layer root, two levels above this recipe
FILESEXTRAPATHS:prepend := "${THISDIR}/../../:"

require recipes-pv/pantavisor/pantavisor.inc

PV = "1.0+git${SRCPV}"

SRC_URI = "file://docs \
           ${PANTAVISOR_URI};branch=${PANTAVISOR_BRANCH};name=pantavisor;destsuffix=pantavisor-git \
           git://gitlab.com/pantacor/docs.git;protocol=https;branch=master;name=pantacor-docs;destsuffix=pantacor-docs-git \
           git://github.com/pantacor/pvr.git;protocol=https;branch=master;name=pvr;destsuffix=pvr-git \
           "

SRCREV_FORMAT        = "pantavisor_pantacor-docs_pvr"
SRCREV_pantavisor    = "${PANTAVISOR_SRCREV}"
SRCREV_pantacor-docs = "073294044a4802279bbc7693f207473c73098707"
SRCREV_pvr           = "09601ee16ff061a6b5b1eff1cd5c66ba9b2c15d5"

do_install[noexec] = "1"

do_deploy() {
    # Resolve a human-readable version from each SCM (tag or short hash)
    pv_ver=$(git -C "${WORKDIR}/pantavisor-git" describe --tags --always 2>/dev/null \
             || git -C "${WORKDIR}/pantavisor-git" rev-parse --short HEAD)
    docs_ver=$(git -C "${WORKDIR}/pantacor-docs-git" describe --tags --always 2>/dev/null \
               || git -C "${WORKDIR}/pantacor-docs-git" rev-parse --short HEAD)
    pvr_ver=$(git -C "${WORKDIR}/pvr-git" describe --tags --always 2>/dev/null \
              || git -C "${WORKDIR}/pvr-git" rev-parse --short HEAD)
    layer_ver=$(git -C "${THISDIR}/../.." describe --tags --always 2>/dev/null \
                || git -C "${THISDIR}/../.." rev-parse --short HEAD)

    # Build staging tree: docs/{versions.json,meta-pantavisor/,pantavisor/,legacy/,pvr/}
    stage="${WORKDIR}/docs-stage/docs"
    install -d "${stage}/meta-pantavisor"
    install -d "${stage}/pantavisor"
    install -d "${stage}/legacy"
    install -d "${stage}/pvr"

    jq -n \
        --arg meta_pantavisor "${layer_ver}" \
        --arg pantavisor      "${pv_ver}" \
        --arg pantacor_docs   "${docs_ver}" \
        --arg pvr             "${pvr_ver}" \
        '{"meta-pantavisor": $meta_pantavisor, "pantavisor": $pantavisor, "pantacor-docs": $pantacor_docs, "pvr": $pvr}' \
        > "${stage}/versions.json"

    cp -r "${WORKDIR}/docs/." "${stage}/meta-pantavisor/"

    if [ -d "${WORKDIR}/pantavisor-git/docs" ]; then
        cp -r "${WORKDIR}/pantavisor-git/docs/." "${stage}/pantavisor/"
    fi

    if [ -d "${WORKDIR}/pantacor-docs-git/content" ]; then
        cp -r "${WORKDIR}/pantacor-docs-git/content/." "${stage}/legacy/"
    fi

    if [ -f "${WORKDIR}/pvr-git/README.md" ]; then
        cp "${WORKDIR}/pvr-git/README.md" "${stage}/pvr/"
    fi

    tar -czf "${DEPLOYDIR}/${PN}-${pv_ver}.tar.gz" -C "${WORKDIR}/docs-stage" .
}

addtask deploy after do_compile before do_build
do_deploy[dirs] += "${DEPLOYDIR}"
