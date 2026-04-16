FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'fsl-image-host-ttys', 'file://args.json', '', d)}"


