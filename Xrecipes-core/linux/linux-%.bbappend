
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = "\
	file://overlayfs.cfg \
	file://pantavisor.cfg \
	file://pvcrypt.cfg \
	file://pvnocma.cfg \
	file://dm.cfg \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', 'file://pantavisor-lz4.cfg', '', d)} \
"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/pantavisor.cfg \
	${WORKDIR}/pvcrypt.cfg \
	${WORKDIR}/pvnocma.cfg \
	${WORKDIR}/overlayfs.cfg \
	${WORKDIR}/dm.cfg \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'squash-lz4', '${WORKDIR}/pantavisor-lz4.cfg', '', d)} \
"

