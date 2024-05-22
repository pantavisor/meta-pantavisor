
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

OVERRIDES =. "mc-${BB_CURRENT_MC}:"

PV_MACHINE_UBOOT_CONFIGS ?= ""
PV_MACHINE_UBOOT_CONFIGS:qemumips ?= "file://pv.qemumips.cfg"

SRC_URI += " \
	file://boot.cmd.pvgeneric \
	file://pv.cfg \
	${PV_MACHINE_UBOOT_CONFIGS} \
" 

uboot_env:mc-default = "boot"
uboot_env_src:mc-default = "boot.txt"
uboot_env_src_frags:mc-default += " boot.cmd.pvgeneric "
uboot_env_suffix:mc-default ?= "scr"
uboot_env_src:pvbsp = ""
uboot_env:pvbsp = ""
uboot_env_suffix:pvbsp = ""

UBOOT_ENV = "${uboot_env}"
UBOOT_ENV_SRC = "${uboot_env_src}"
UBOOT_ENV_SRC_FRAGS = "${uboot_env_src_frags}"
UBOOT_ENV_SUFFIX = "${uboot_env_suffix}"

do_prepcompile() {

	if [ -z "${UBOOT_ENV}" -o -z "${UBOOT_ENV_SRC_FRAGS}" ]; then
		return 0
	fi

	echo > ${WORKDIR}/${UBOOT_ENV_SRC}
	for frag in ${UBOOT_ENV_SRC_FRAGS}; do
		cat ${WORKDIR}/$frag >> ${WORKDIR}/${UBOOT_ENV_SRC}
	done
}

addtask prepcompile before do_configure do_compile after do_fetch do_patch

