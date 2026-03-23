SUMMARY = "PVCM Zephyr Shell - MCU container demo"
DESCRIPTION = "Zephyr application demonstrating PVCM protocol with \
interactive shell commands (pv status, pv containers) over RPMsg/UART. \
Includes mandatory heartbeat, log backend, and protocol server."

inherit zephyr-sample

ZEPHYR_SRC_DIR = "${TOPDIR}/workspace/sources/pantavisor/sdk/zephyr/samples/pvcm-shell"

# Pantavisor SDK as a Zephyr module
ZEPHYR_EXTRA_MODULES = "${TOPDIR}/workspace/sources/pantavisor/sdk/zephyr"
