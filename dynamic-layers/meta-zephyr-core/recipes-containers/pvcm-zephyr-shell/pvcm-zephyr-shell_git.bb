SUMMARY = "PVCM Zephyr Shell - MCU container demo"
DESCRIPTION = "Zephyr application demonstrating PVCM protocol with \
interactive shell commands (pv status, pv containers) over RPMsg/UART. \
Includes mandatory heartbeat, log backend, and protocol server."

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit zephyr-pvrexport

ZEPHYR_SRC_DIR = "${TOPDIR}/workspace/sources/pantavisor/sdk/zephyr/samples/pvcm-shell"

# Pantavisor SDK as a Zephyr module
ZEPHYR_EXTRA_MODULES = "${TOPDIR}/workspace/sources/pantavisor/sdk/zephyr"

SRC_URI += "file://pvcm-zephyr-shell.args.json"

# native_sim fix: the NSI Makefile uses NSI_CC without --sysroot.
# Patch nsi_config after cmake generates it.
do_configure:append() {
    if [ -f ${B}/zephyr/NSI/nsi_config ]; then
        sed -i "s|^NSI_CC:=\(.*\)|NSI_CC:=\1 --sysroot=${STAGING_DIR_TARGET}|" \
            ${B}/zephyr/NSI/nsi_config
    fi
}
