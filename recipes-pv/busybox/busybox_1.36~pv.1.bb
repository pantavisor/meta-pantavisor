FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

S = "${WORKDIR}/git"

require busybox.inc

DEPENDS:append = "\
	       libcap \
"

REPENDS:append = "\
	       libcap \
"

SRC_URI = " \
	git://github.com/pantavisor/busybox-pv;protocol=https;branch=pv/1_35_stable \
	file://defconfig \
	file://trim.cfg \
	file://pantavisor.cfg \
	file://debug.patch \
"
SRC_URI += " ${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://0001-bootchartd_on_smm.patch', '', d)}"
SRC_URI += " ${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://enable_bootchartd.cfg', '', d)}"

SRCREV = "3bcf56d2f6aeacc0606e71e364762c89a61ab895"

