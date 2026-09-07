FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'core-image-host-ttys', 'file://args.json', '', d)}"

