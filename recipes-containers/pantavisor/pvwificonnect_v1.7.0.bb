SUMMARY = "Pantavisor WiFi Connect container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

DEPENDS:append = " jq-native"

IMAGE_BASENAME = "pvwificonnect"

PVPKG_DESCRIPTION ?= "Manages Wi-Fi connections on Pantacor-enabled devices."
PVPKG_PACKAGE_URL ?= "https://gitlab.com/pantacor/pvwificonnect"
PVPKG_URL ?= "${PVPKG_PACKAGE_URL}"

PV_DOCKER_NAME ?= "registry.gitlab.com/pantacor/pvwificonnect"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

# Smaller than core-image: `inherit image` drops packagegroup-core-boot
# (eudev, sysvinit, …) which a pvr container doesn't need. base-files +
# base-passwd reproduce the busybox:musl Docker base — the /proc /sys /dev
# mountpoint dirs and /etc/passwd that the container's lxc.mount.auto (cgroup)
# and user setup require. Without them the container aborts at start.
IMAGE_INSTALL += "busybox pvwificonnect-app base-files base-passwd"

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

    # Add docker image metadata to src.json so hub.pantacor.com can display
    # the image name and version for this container.
    if [ -f ${PN}/src.json ]; then
        jq --arg name "${PV_DOCKER_NAME}" --arg tag "${PV}" \
            '. + { docker_name: $name, docker_tag: $tag }' \
            ${PN}/src.json > ${PN}/src.json.tmp && mv ${PN}/src.json.tmp ${PN}/src.json
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
