FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

DEPENDS:append = " libcap"

SRC_URI += " \
    file://trim.cfg \
    file://pantavisor.cfg \
    file://pv-1.36.1/0001-add-caps-flag-to-make-nsenter-also-adopt-the-same-ca.patch \
    file://pv-1.36.1/0002-fix-capget-to-be-run-before-switching-namespaces.patch \
    file://pv-1.36.1/0003-nsenter.c-add-C-cgropup-option-similar-to-util-linux.patch \
    file://pv-1.36.1/0004-add-support-for-ROOTFSDIR-and-MDEV_CONF-envs.patch \
    file://pv-1.36.1/0005-add-support-for-FOLLOW_X_ROOT-env-superseed-ROOTFSDI.patch \
    file://pv-1.36.1/0006-fix-depends-in-mdev.c-for-FOLLOW_X_ROOT-config.patch \
    file://pv-1.36.1/0007-add-FOLLOW_X_PID-support-for-pantavisor-mdev.patch \
    file://pv-1.36.1/0008-fix-create_and_bind_to_netlink-setting-sa.nl_pid-to-.patch \
    file://pv-1.36.1/0009-Improve-mdev-MODALIAS-support-loading-pci-bus-driver.patch \
    file://pv-1.36.1/0010-add-support-for-unix_proxy-env-for-wget.patch \
    file://pv-1.36.1/0011-unshare-add-C-cgroup-option-similar-to-util-linux.patch \
    file://debug.patch \
"
SRC_URI += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://0001-bootchartd_on_smm.patch', '', d)}"
SRC_URI += "${@bb.utils.contains('PANTAVISOR_FEATURES', 'bootchartd', 'file://enable_bootchartd.cfg', '', d)}"

# meta-pantavisor ships busybox as a single, unsplit package and manages
# device/init handling (mdev, syslog, etc.) itself, so drop upstream's
# subpackage split and its automatic RDEPENDS/RRECOMMENDS on them.
# (:remove rather than reassigning PACKAGES, since busybox.inc builds the
# list with "=+" and a later plain/=+ override here would not undo that.)
PACKAGES:remove = "${PN}-httpd ${PN}-udhcpd ${PN}-udhcpc ${PN}-syslog ${PN}-mdev ${PN}-hwclock"
RRECOMMENDS:${PN} = ""
RDEPENDS:${PN} = "libcap"
RDEPENDS:${PN}-ptest = ""

PROVIDES:${PN}:append = " busybox busybox-hwclock busybox-udhcpc busybox-syslog"
RPROVIDES:${PN}:append = " busybox busybox-hwclock busybox-udhcpc busybox-syslog"

# busybox.inc's do_install still installs upstream's generic mdev and
# udhcpd init artifacts whenever CONFIG_MDEV/CONFIG_UDHCPD are enabled
# (pantavisor.cfg/defconfig enable both). Pantavisor supplies its own
# device management, so strip them rather than ship two competing setups.
do_install:append () {
	rm -rf ${D}${sysconfdir}/init.d/mdev
	rm -rf ${D}${sysconfdir}/mdev.conf
	rm -rf ${D}${sysconfdir}/mdev
	rm -rf ${D}${sysconfdir}/init.d/busybox-udhcpd
}
