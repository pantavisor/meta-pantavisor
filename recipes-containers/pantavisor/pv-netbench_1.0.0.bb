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

IMAGE_INSTALL += "busybox base-files base-passwd nftables curl"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# Must be ${PN}.args.json so container-pvrexport merges PVR_APP_ADD_ROLES into it.
SRC_URI += "file://pv-netbench.args.json \
            file://config.json \
            file://netbench.sh \
"

PVR_APP_ADD_GROUP = "platform"
PVR_APP_ADD_ROLES = "mgmt"
PVR_APP_ADD_EXTRA_ARGS += " --volume ovl:/tmp:permanent"

PVR_SIG_ADD_ARGS = "--part ${PN}"

# Baked into /etc/netbench.env; override per image.
BENCH_MODE ?= "pvsm"
BENCH_HUB_HOST ?= "api.pantahub.com"

install_netbench() {
    install -d ${IMAGE_ROOTFS}/usr/local/bin
    install -m 0755 ${WORKDIR}/netbench.sh ${IMAGE_ROOTFS}/usr/local/bin/netbench

    install -d ${IMAGE_ROOTFS}${sysconfdir}
    printf 'PH_BENCH_MODE=%s\nPH_HUB_HOST=%s\n' "${BENCH_MODE}" "${BENCH_HUB_HOST}" \
        > ${IMAGE_ROOTFS}${sysconfdir}/netbench.env

    install -d ${IMAGE_ROOTFS}/proc ${IMAGE_ROOTFS}/sys ${IMAGE_ROOTFS}/tmp
}

ROOTFS_POSTPROCESS_COMMAND += "install_netbench; "

# ROOTFS_POSTPROCESS_COMMAND bodies are not in do_rootfs's signature.
do_rootfs[vardeps] += "BENCH_MODE BENCH_HUB_HOST"
