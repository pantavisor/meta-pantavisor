SUMMARY = "pv-mqtt-sdk Pantahub MQTT agent container"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit image container-pvrexport

DEPENDS:append = " jq-native"

IMAGE_BASENAME = "pv-mqtt-sdk"

PVPKG_DESCRIPTION ?= "Pantahub MQTT agent: push updates, device-meta and user-meta for Pantavisor devices with remote control disabled."
PVPKG_PACKAGE_URL ?= "https://github.com/pantavisor/pv-mqtt-sdk"
PVPKG_URL ?= "${PVPKG_PACKAGE_URL}"

PV_DOCKER_NAME ?= "ghcr.io/pantavisor/pv-mqtt-sdk"

IMAGE_FSTYPES = "pvrexportit"

# Same minimal base as pvwificonnect: base-files + base-passwd reproduce the
# busybox:musl Docker base (mountpoint dirs, /etc/passwd) lxc needs.
IMAGE_INSTALL += "busybox pv-mqtt-sdk-app ca-certificates base-files base-passwd"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://args.json \
            file://config.json \
"

# PV_ROLES (mgmt: the agent installs revisions and writes meta through
# pv-ctrl) is in args.json: PVR_APP_ADD_ROLES would write a ${PN}.args.json
# holding only the roles, which container-pvrexport prefers over args.json.
PVR_APP_ADD_GROUP = "platform"
# Credentials, the revision queue and the in-flight record must survive
# reboots: an update reboots the device mid-install.
PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/var/pv-mqtt-sdk:permanent \
"

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

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport
