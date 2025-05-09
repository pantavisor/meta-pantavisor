FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

OVERRIDES =. "mc-${BB_CURRENT_MC}:"

PV_MACHINE_UBOOT_CONFIGS ?= ""
PV_MACHINE_UBOOT_CONFIGS:qemumips ?= "file://pv.qemumips.cfg"

PV_BOOT_OEMARGS ?= ""

SRC_URI += " \
	file://boot.cmd.pvgeneric \
	file://pv.cfg \
	file://oemEnv.txt \
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

	# example: meta-sunxi is doing their own compilation in do_compile so
	# lets ensure our source is also available in boot.cmd
	cp ${WORKDIR}/${UBOOT_ENV_SRC} ${WORKDIR}/boot.cmd
	cp ${WORKDIR}/${UBOOT_ENV_SRC} ${WORKDIR}/boot.cmd.in
}

addtask prepcompile before do_configure do_compile after do_fetch do_patch

do_deploy:append() {
	cat ${WORKDIR}/oemEnv.txt | \
		sed -e 's/@@PV_BOOT_OEMARGS@@/${PV_BOOT_OEMARGS}/' \
		> ${WORKDIR}/oemEnv.txt.final
	install -D -m 644 ${WORKDIR}/oemEnv.txt.final ${DEPLOYDIR}/oemEnv.txt
}
