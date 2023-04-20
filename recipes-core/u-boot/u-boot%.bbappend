
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += " file://boot.cmd file://pv.cfg " 
UBOOT_ENV = "boot"
UBOOT_ENV_SUFFIX = "scr"

