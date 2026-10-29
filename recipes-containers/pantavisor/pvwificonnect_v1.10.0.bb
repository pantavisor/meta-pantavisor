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

# Optional pre-provisioned station network, written as the `network` block
# of config.json: the device joins it on every boot before falling back to
# its AP. Set both from an uncommitted local config, never in the layer.
PVWIFICONNECT_NETWORK_SSID ?= ""
PVWIFICONNECT_NETWORK_PASSWORD ?= ""

ROOTFS_POSTPROCESS_COMMAND += "set_preset_network; "
set_preset_network() {
    [ -n "${PVWIFICONNECT_NETWORK_SSID}" ] || return 0
    cfg=${WORKDIR}/${PV_CONFIG_OVERLAY_DIR}/var/pvwificonnect/config.json
    jq --arg ssid "${PVWIFICONNECT_NETWORK_SSID}" \
       --arg password "${PVWIFICONNECT_NETWORK_PASSWORD}" \
       '. + { network: { ssid: $ssid, password: $password } }' \
       $cfg > $cfg.new
    mv -f $cfg.new $cfg
}

PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
"

PVR_APP_ADD_GROUP = "platform"
# mgmt: pv-ctrl's /config2, /steps and /objects, to read a Wi-Fi network
# preset in the revision's OEM config (PVWIFICONNECT_NETWORK_*).
PVR_APP_ADD_ROLES = "mgmt"

# Sign including config (override --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

ROOTFS_POSTPROCESS_COMMAND += "set_hostname; "

# Make the container's hostname its own name: overwrite the /etc/hostname
# (and the matching /etc/hosts entry base-files wrote, whose
# `hostname:pn-base-files` default is `${MACHINE}`) so pvwificonnect runs
# under a stable, machine-independent identity.
set_hostname() {
    echo "${PN}" > ${IMAGE_ROOTFS}${sysconfdir}/hostname
    sed -i "s/^127.0.1.1.*/127.0.1.1 ${PN}/" ${IMAGE_ROOTFS}${sysconfdir}/hosts
}

pvr_app_postprocess() {
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

}

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport
