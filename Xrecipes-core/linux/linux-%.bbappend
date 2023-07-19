
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = "\
	file://overlayfs.cfg \
	file://pantavisor.cfg \
	file://pvcrypt.cfg \
	file://pvnocma.cfg \
	file://dm.cfg \
"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/pantavisor.cfg \
	${WORKDIR}/pvcrypt.cfg \
	${WORKDIR}/pvnocma.cfg \
	${WORKDIR}/overlayfs.cfg \
	${WORKDIR}/dm.cfg \
"

