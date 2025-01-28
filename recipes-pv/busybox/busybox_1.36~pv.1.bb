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
	git://gitlab.com/pantacor/busybox.git;protocol=https;branch=pv/1_35_stable \
	file://defconfig \
	file://trim.cfg \
	file://pantavisor.cfg \
	file://debug.patch \
"
SRC_URI += " ${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://0001-bootchartd_on_smm.patch', '', d)}"
SRC_URI += " ${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://enable_bootchartd.cfg', '', d)}"

SRCREV = "c64d10b37d647b4a38c53034bc50b76e76d53d4e"
#SRCREV = "c0e215239b7085d5a23524ca32afaaa8eacc8f63"

