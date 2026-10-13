FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

OVERRIDES =. "mc-${BB_CURRENT_MC}:"

PV_MACHINE_UBOOT_CONFIGS ?= ""
PV_MACHINE_UBOOT_CONFIGS:qemumips ?= "file://pv.qemumips.cfg"

# colibri-imx6ull is a NAND-only module in this layer; drop the unused "emmc"
# UBOOT_CONFIG variant that tezi.conf adds ("rawnand emmc recoverytezi"). Its
# colibri-imx6ull-emmc_defconfig has no MTD/UBI, so the CMD_UBIFS enabled by
# pv.colibri-imx6ull.cfg fails to compile there. Scoped to the tezi-recovery
# multiconfig (where tezi.conf sets UBOOT_CONFIG) via the mc override above.
UBOOT_CONFIG:mc-tezi-recovery:colibri-imx6ull = "rawnand recoverytezi"

PV_BOOT_OEMARGS ?= ""

# Carrier board name for U-Boots that build fdtfile from fdt_board (Toradex).
# Rendered into oemEnv.txt as pv_default_fdt_board; the boot scripts apply it
# only while the U-Boot env has no custom fdt_board.
PV_UBOOT_DEFAULT_FDT_BOARD ?= ""

# NAND partition table (mtdparts syntax without the "mtdparts=" prefix). When
# set it is rendered into oemEnv.txt as U-Boot's mtdparts so boot scripts can
# address partitions by name (fitA/fitB for pv-uboot-ab).
PV_UBOOT_MTDPARTS ?= ""

# pv-uboot-ab boots the FIT from raw MTD partitions (boot.cmd.pvab); everything
# else uses the generic script.
PV_UBOOT_BOOT_SCRIPT = "${@bb.utils.contains('PANTAVISOR_FEATURES', 'pv-uboot-ab', 'boot.cmd.pvab', 'boot.cmd.pvgeneric', d)}"

SRC_URI += " \
	file://${PV_UBOOT_BOOT_SCRIPT} \
	file://pv.cfg \
	file://pv.distroboot.cfg \
	file://oemEnv.txt \
	${PV_MACHINE_UBOOT_CONFIGS} \
" 

uboot_env:mc-default = "boot"
uboot_env_src:mc-default = "boot.txt"
uboot_env_src_frags:mc-default += " ${PV_UBOOT_BOOT_SCRIPT} "
uboot_env_suffix:mc-default ?= "scr"

uboot_env_src:pvbsp = ""
uboot_env:pvbsp = ""
uboot_env_src_frags:pvbsp:remove = "${PV_UBOOT_BOOT_SCRIPT}"
uboot_env_suffix:pvbsp = ""

uboot_env_src:pvapp = ""
uboot_env_src_frags:pvapp:remove = "${PV_UBOOT_BOOT_SCRIPT}"
uboot_env:pvapp = ""
uboot_env_suffix:pvapp = ""

UBOOT_ENV = "${uboot_env}"
UBOOT_ENV_SRC = "${uboot_env_src}"
UBOOT_ENV_SRC_FRAGS = "${uboot_env_src_frags}"
UBOOT_ENV_SUFFIX = "${uboot_env_suffix}"

do_prepcompile() {

	if [ -z "${UBOOT_ENV}" -o -z "${UBOOT_ENV_SRC_FRAGS}" -o -z "${UBOOT_ENV_SRC}" ]; then
		return 0
	fi

	echo > ${WORKDIR}/${UBOOT_ENV_SRC}
	for frag in ${UBOOT_ENV_SRC_FRAGS}; do
		cat ${WORKDIR}/$frag >> ${WORKDIR}/${UBOOT_ENV_SRC}
	done

	# example: meta-sunxi is doing their own compilation in do_compile so
	# lets ensure our source is also available in boot.cmd
	cp ${WORKDIR}/${UBOOT_ENV_SRC} ${WORKDIR}/boot.cmd
	cp ${WORKDIR}/${UBOOT_ENV_SRC} ${WORKDIR}/boot.cmd.in
}

addtask prepcompile before do_configure do_compile after do_fetch do_patch

do_deploy:append() {
	if [ "${PN}" = "u-boot-distro-boot" ]; then
		return 0
	fi
	cat ${WORKDIR}/oemEnv.txt | \
		sed -e 's/@@PV_BOOT_OEMARGS@@/${PV_BOOT_OEMARGS}/' \
		> ${WORKDIR}/oemEnv.txt.final
	if [ -n "${PV_UBOOT_DEFAULT_FDT_BOARD}" ]; then
		echo "pv_default_fdt_board=${PV_UBOOT_DEFAULT_FDT_BOARD}" >> ${WORKDIR}/oemEnv.txt.final
	fi
	if [ -n "${PV_UBOOT_MTDPARTS}" ]; then
		echo "mtdparts=mtdparts=${PV_UBOOT_MTDPARTS}" >> ${WORKDIR}/oemEnv.txt.final
	fi
	install -D -m 644 ${WORKDIR}/oemEnv.txt.final ${DEPLOYDIR}/oemEnv.txt
}
