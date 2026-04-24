SUMMARY = "Pantavisor WiFi Connect container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

DEPENDS:append = " jq-native"

IMAGE_BASENAME = "pvwificonnect"

PVPKG_DESCRIPTION ?= "Manages Wi-Fi connections on Pantacor-enabled devices."
PVPKG_PACKAGE_URL ?= "https://gitlab.com/pantacor/pvwificonnect"
PVPKG_URL ?= "${PVPKG_PACKAGE_URL}"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

IMAGE_INSTALL += "busybox pvwificonnect-app"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://args.json \
            file://config.json \
            file://pvwificonnect-config \
"

PV_CONFIG_OVERLAY_DIR = "pvwificonnect-config"

PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
"

PVR_APP_ADD_GROUP = "platform"

# Sign including config (override --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

do_image_pvrexportit:append() {
    export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
    export PVR_DISABLE_SELF_UPGRADE=1
    cd ${PVSTATE}

    args_json=""
    if [ -f ${WORKDIR}/${PN}.args.json ]; then
        args_json="${WORKDIR}/${PN}.args.json"
    elif [ -f ${WORKDIR}/args.json ]; then
        args_json="${WORKDIR}/args.json"
    fi

    base='{
        "name": "${PN}",
        "version": "${PV}",
        "arch": "${DOCKER_ARCH}",
        "description": "${PVPKG_DESCRIPTION}",
        "license": "${LICENSE}",
        "url": "${PVPKG_URL}",
        "package_url": "${PVPKG_PACKAGE_URL}"
    }'

    if [ -n "$args_json" ]; then
        echo "$base" | jq --slurpfile args "$args_json" \
            '. + { src_extra: { args: $args[0] } }' > ${PN}/pvpkg.json
    else
        echo "$base" | jq '.' > ${PN}/pvpkg.json
    fi

    pvr add
    pvr commit
    pvr sig up
    pvr add
    pvr commit
    pvr export ${IMGDEPLOYDIR}/${PN}.pvrexport.tgz
}

# pvroot-image expects do_deploy to provide the .pvrexport.tgz
# do_image_complete sstate also deploys it, so use symlink to avoid conflict
fakeroot do_deploy() {
    :
}

addtask deploy after do_image_complete before do_build
