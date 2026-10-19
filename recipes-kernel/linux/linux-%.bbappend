
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
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'wakelocks', 'file://wakelock.cfg', '', d)} \
	${TAILSCALE_KERNEL_SRC_URI} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'file://pantavisor-lz4.cfg', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'caam-nxp', 'file://caam-nxp.cfg', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'dcp', 'file://dcp.cfg', '', d)} \
"


PANTAVISOR_KERNEL_FRAGMENTS = " \
	${WORKDIR}/pantavisor.cfg \
	${WORKDIR}/pvcrypt.cfg \
	${WORKDIR}/overlayfs.cfg \
	${WORKDIR}/dm.cfg \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'wakelocks', '${WORKDIR}/wakelock.cfg', '', d)} \
	${TAILSCALE_KERNEL_FRAGMENT} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '${WORKDIR}/pantavisor-lz4.cfg', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'caam-nxp', '${WORKDIR}/caam-nxp.cfg', '', d)} \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'dcp', '${WORKDIR}/dcp.cfg', '', d)} \
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

# With cgroup2 the container device rules are enforced by a cgroup BPF
# program. The layer adds no kernel options for it, so fail the build if the
# kernel config lacks them. Only real kernels (those inheriting kernel.bbclass)
# get the check, which leaves linux-dummy alone.
PV_KERNEL_CGROUP_VERSION = "${PANTAVISOR_CGROUP_VERSION}"

python do_pv_check_cgroup_bpf() {
    if d.getVar('PV_KERNEL_CGROUP_VERSION') != '2':
        return
    with open(d.expand('${B}/.config')) as f:
        config = f.read().splitlines()
    missing = [o for o in ('CONFIG_BPF_SYSCALL', 'CONFIG_CGROUP_BPF')
               if '%s=y' % o not in config]
    if missing:
        bb.fatal("PV_SYSTEM_CGROUP_VERSION=2 needs cgroup BPF for container "
                 "device control, but the kernel config lacks: %s=y.\n"
                 "Either enable them in the BSP kernel config, or set "
                 "PANTAVISOR_CGROUP_VERSION = \"1\" (or \"auto\")."
                 % '=y, '.join(missing))
}
do_pv_check_cgroup_bpf[vardeps] += "PV_KERNEL_CGROUP_VERSION PANTAVISOR_CGROUP_VERSION"

python () {
    # an explicit PANTAVISOR_CONFIG[PV_SYSTEM_CGROUP_VERSION] wins, as in pantavisor
    version = d.getVarFlag('PANTAVISOR_CONFIG', 'PV_SYSTEM_CGROUP_VERSION')
    if version:
        d.setVar('PV_KERNEL_CGROUP_VERSION', d.expand(version))
    if bb.data.inherits_class('kernel', d):
        bb.build.addtask('do_pv_check_cgroup_bpf', 'do_compile', 'do_configure', d)
}

