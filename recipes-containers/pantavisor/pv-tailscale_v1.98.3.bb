SUMMARY = "Pantavisor Tailscale VPN container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-tailscale"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

# tailscale + tailscaled are built from source by meta-networking's tailscale
# recipe, which cross-compiles the Go module rooted at tailscale.com
# (GO_IMPORT = "tailscale.com"). iptables gives tailscaled a firewall backend
# (the kernel side is enabled by the `tailscale` PANTAVISOR_FEATURE, which pulls
# in tailscale-iptables.cfg: CONFIG_TUN, CONFIG_WIREGUARD, NAT/MARK targets);
# ca-certificates lets it reach the coordination server over HTTPS.
#
# base-files + base-passwd reproduce the busybox:musl Docker base — the
# /proc /sys /dev mountpoint dirs and /etc/passwd that the container's
# lxc.mount.auto (cgroup) and user setup require. Without them the container
# aborts at start (same rationale as pvwificonnect).
IMAGE_INSTALL += "busybox tailscale iptables ca-certificates base-files base-passwd"

# Document/force the upstream Go import path the meta-networking recipe builds
# against, so the provenance of the shipped client is explicit at the layer that
# composes the container.
GO_IMPORT = "tailscale.com"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://args.json \
            file://config.json \
            file://pv-tailscale-start.sh \
"

# tailscaled state must survive reboots/updates; /tmp is a scratch overlay.
PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
    --volume ovl:/var/lib/tailscale:permanent \
"

PVR_APP_ADD_GROUP = "platform"

# pvroot-image expects do_deploy to provide the .pvrexport.tgz
# do_image_complete sstate also deploys it, so use a no-op to avoid conflict
fakeroot do_deploy() {
    :
}

addtask deploy after do_image_complete before do_build

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-tailscale-start.sh ${IMAGE_ROOTFS}${bindir}/pv-tailscale-start

    # tailscaled persistent state directory + the runtime socket/tun dirs
    install -d ${IMAGE_ROOTFS}/var/lib/tailscale
    install -d ${IMAGE_ROOTFS}/var/run/tailscale
    install -d ${IMAGE_ROOTFS}/dev/net
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "
