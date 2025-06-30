
OVERRIDES =. "mc-${BB_CURRENT_MC}:"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

INITRAMFS_IMAGE ?= "pantavisor-initramfs"

KERNEL_IMAGETYPES:qemumips += "uImage"
KERNEL_CLASSES:qemumips += "kernel-uimage"

KBUILD_DEFCONFIG:qemumips = "malta_defconfig"
KERNEL_DEVICETREE:qemumips = "mti/malta.dtb"

# Determine which kernel fragment to include based on IMAGE_INSTALL
# We check if 'nftables' is in IMAGE_INSTALL.
# If it is, we assume nftables is the desired firewall backend.
# Otherwise, we default to the iptables-legacy configuration.
TAILSCALE_KERNEL_SRC_URI = ""
TAILSCALE_KERNEL_FRAGMENT = ""
python () {
    if not bb.utils.contains('PANTAVISOR_FEATURES', 'tailscale', True, False, d):
        return

    if bb.utils.contains('IMAGE_INSTALL', 'nftables', True, False, d):
        d.setVar('TAILSCALE_KERNEL_FRAGMENT', '${WORKDIR}/tailscale-nftables.cfg')
        d.setVar('TAILSCALE_KERNEL_SRC_URI', 'file://tailscale-nftables.cfg')
    else:
        # If nftables is NOT in IMAGE_INSTALL, assume iptables-legacy compatibility
        d.setVar('TAILSCALE_KERNEL_FRAGMENT', '${WORKDIR}/tailscale-iptables.cfg')
        d.setVar('TAILSCALE_KERNEL_SRC_URI', 'file://tailscale-iptables.cfg')
}


PANTAVISOR_SRC_URI = " \
	file://overlayfs.cfg \
	file://pantavisor.cfg \
	file://pvcrypt.cfg \
	file://dm.cfg \
	${TAILSCALE_KERNEL_SRC_URI} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'file://pantavisor-lz4.cfg', '', d)} \
"


PANTAVISOR_KERNEL_FRAGMENTS = " \
	${WORKDIR}/pantavisor.cfg \
	${WORKDIR}/pvcrypt.cfg \
	${WORKDIR}/overlayfs.cfg \
	${WORKDIR}/dm.cfg \
	${TAILSCALE_KERNEL_FRAGMENT} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '${WORKDIR}/pantavisor-lz4.cfg', '', d)} \
"

SRC_URI:append = " \
	${@bb.utils.contains_any('DISTRO_FEATURES', 'pantavisor-system pantavisor-kernel', '${PANTAVISOR_SRC_URI}', '', d)} \
"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${@bb.utils.contains_any('DISTRO_FEATURES', 'pantavisor-system pantavisor-kernel', '${PANTAVISOR_KERNEL_FRAGMENTS}', '', d)} \
"

COMPATIBLE_MACHINE:qemuarm-pv = "qemuarm-pv"


# for bootscript in fitimage
uboot_env:mc-default = "boot"
uboot_env_suffix:mc-default ?= "scr"
uboot_env_src:pvbsp = ""
uboot_env_suffix:pvbsp = ""

UBOOT_ENV = "${uboot_env}"
UBOOT_ENV_SUFFIX = "${uboot_env_suffix}"

