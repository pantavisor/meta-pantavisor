
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

PV_MACHINE_UBOOT_CONFIGS ?= ""
PV_MACHINE_UBOOT_CONFIGS:qemumips ?= "file://pv.qemumips.cfg"

SRC_URI += " \
	file://boot.cmd.pvgeneric \
	file://pv.cfg \
	${PV_MACHINE_UBOOT_CONFIGS} \
" 

UBOOT_ENV_SRC = "boot.cmd"
UBOOT_ENV_SRC_FRAGS += " boot.cmd.pvgeneric "
UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"

do_prepcompile() {

	if [ -z "${UBOOT_ENV_SRC_FRAGS}" ]; then
		return 0
	fi

	echo > ${WORKDIR}/${UBOOT_ENV_SRC}
	for frag in ${UBOOT_ENV_SRC_FRAGS}; do
		cat ${WORKDIR}/$frag >> ${WORKDIR}/${UBOOT_ENV_SRC}
	done
}

addtask prepcompile before do_compile after do_patch

