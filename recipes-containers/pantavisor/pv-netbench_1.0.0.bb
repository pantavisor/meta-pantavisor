SUMMARY = "Pantahub network usage benchmark container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-netbench"

PVPKG_DESCRIPTION ?= "Measure Pantahub network usage and publish it as device-meta."
PVPKG_PACKAGE_URL ?= "https://gitlab.com/pantacor/pv-netbench"
PVPKG_URL ?= "${PVPKG_PACKAGE_URL}"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

# Native rootfs: the tools netbench needs, built by the distro for the target
# arch. busybox provides sh/awk/date; nftables the byte counters; curl the
# device-meta PUT and the driver-load call over the pv-ctrl unix socket. The
# Hub IP comes from /proc/net/tcp, so no resolver/nslookup is needed.
IMAGE_INSTALL += "busybox base-files base-passwd nftables curl"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# Named pv-netbench.args.json (not args.json): when PVR_APP_ADD_ROLES is set,
# container-pvrexport merges the roles into ${PN}.args.json. A plain args.json
# would instead be shadowed by a fresh roles-only ${PN}.args.json, dropping the
# caps below.
SRC_URI += "file://pv-netbench.args.json \
            file://config.json \
            file://netbench.sh \
"

# platform group keeps the host network namespace (sees the real uplink);
# mgmt role grants the root-only /pantavisor/pv-ctrl socket for device-meta.
PVR_APP_ADD_GROUP = "platform"
PVR_APP_ADD_ROLES = "mgmt"
PVR_APP_ADD_EXTRA_ARGS += " --volume ovl:/tmp:permanent"

# Sign including config (override --noconfig default from container-pvrexport).
PVR_SIG_ADD_ARGS = "--part ${PN}"

# The measured architecture's label, baked so the device is self-describing.
# native-remote for the control.remote=1 image, pvsm for control.remote=0.
# Overridden per image via a build variable; the script sources this file.
BENCH_MODE ?= "pvsm"
BENCH_HUB_HOST ?= "api.pantahub.com"

install_netbench() {
    install -d ${IMAGE_ROOTFS}/usr/local/bin
    install -m 0755 ${WORKDIR}/netbench.sh ${IMAGE_ROOTFS}/usr/local/bin/netbench

    install -d ${IMAGE_ROOTFS}${sysconfdir}
    printf 'PH_BENCH_MODE=%s\nPH_HUB_HOST=%s\n' "${BENCH_MODE}" "${BENCH_HUB_HOST}" \
        > ${IMAGE_ROOTFS}${sysconfdir}/netbench.env

    # /proc /sys mountpoints the container's lxc.mount.auto expects.
    install -d ${IMAGE_ROOTFS}/proc ${IMAGE_ROOTFS}/sys ${IMAGE_ROOTFS}/tmp
}

ROOTFS_POSTPROCESS_COMMAND += "install_netbench; "

# install_netbench bakes BENCH_MODE/BENCH_HUB_HOST into netbench.env, but it
# runs from ROOTFS_POSTPROCESS_COMMAND whose function-body var references are
# not automatically added to do_rootfs's signature. Without this, changing
# BENCH_MODE (e.g. native vs pvsm overlay) leaves do_rootfs's hash unchanged and
# bitbake reuses the other variant's sstate -- the container ships the wrong
# label. Make the dependency explicit so each variant rebuilds.
do_rootfs[vardeps] += "BENCH_MODE BENCH_HUB_HOST"
