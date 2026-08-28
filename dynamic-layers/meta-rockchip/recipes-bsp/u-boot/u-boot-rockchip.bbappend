FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# u-boot-rockchip runs the vendor's make.sh, which fights Pantavisor's boot
# setup in four places. Each patch carries its own rationale:
#   0001 - make.sh regenerates .config from its own defconfig, dropping the
#          pv.cfg/pv.distroboot.cfg fragments OE already merged; re-merge them.
#   0002 - the compiled-in bootcmd (RKIMG_BOOTCOMMAND, a C macro) ignores
#          CONFIG_BOOTCOMMAND and boots the vendor Android boot.img first,
#          which has no root=/initrd for pantavisor.
#   0003 - this fork's cmd/source.c doesn't stop at mkimage's zero terminator,
#          so `source` runs off the size table into the script bytes.
#   0004 - distro_bootcmd only scans bootable-flagged partitions, then falls
#          back to partition 1 (the raw loader region); pv_e2fsgrow drops the
#          flag on autogrow, so a board boots once and then fails.
SRC_URI += " \
	file://0001-make.sh-merge-pv-kconfig-fragments.patch \
	file://0002-rockchip-common-run-distro-bootcmd.patch \
	file://0003-cmd-source-zero-terminated-size-table.patch \
	file://0004-distro-bootcmd-scan-all-partitions.patch \
"

export PV_KCONFIG_FRAGS = "${WORKDIR}/pv.cfg ${WORKDIR}/pv.distroboot.cfg"
