SUMMARY = "SysV init scripts"
HOMEPAGE = "https://github.com/fedora-sysv/initscripts"
DESCRIPTION = "Initscripts provide the basic system startup initialization scripts for the system.  These scripts include actions such as filesystem mounting, fsck, RTC manipulation and other actions routinely performed at system startup.  In addition, the scripts are also used during system shutdown to reverse the actions performed at startup."
SECTION = "base"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://functions;beginline=7;endline=7;md5=829e563511c9a1d6d41f17a7a4989d6a"
PR = "r155"

INHIBIT_DEFAULT_DEPS = "1"

SRC_URI = "file://functions \
           file://hostname.sh \
           file://banner.sh \
           file://bootmisc.sh \
           file://single \
           file://sendsigs \
           file://volatiles \
           file://urandom \
           file://rmnologin.sh \
           file://dmesg.sh \
           file://logrotate-dmesg.conf \
"

S = "${WORKDIR}"

KERNEL_VERSION = ""

DEPENDS:append = " update-rc.d-native"
PACKAGE_WRITE_DEPS:append = " ${@bb.utils.contains('DISTRO_FEATURES','systemd','systemd-systemctl-native','',d)}"

PACKAGES =+ "${PN}-functions ${PN}-sushell"
RDEPENDS:${PN} = "initd-functions \
                  ${@bb.utils.contains('DISTRO_FEATURES','selinux','${PN}-sushell','',d)} \
                  init-system-helpers-service \
		 "
# Recommend pn-functions so that it will be a preferred default provider for initd-functions
RRECOMMENDS:${PN} = "${PN}-functions"
RPROVIDES:${PN}-functions = "initd-functions"
RCONFLICTS:${PN}-functions = "lsbinitscripts"
FILES:${PN}-functions = "${sysconfdir}/init.d/functions*"
FILES:${PN}-sushell = "${base_sbindir}/sushell"

HALTARGS ?= "-d -f"

do_configure() {
	:
}

do_install () {
#
# Create directories and install device independent scripts
#
	install -d ${D}${sysconfdir}/init.d
	install -d ${D}${sysconfdir}/rcS.d
	install -d ${D}${sysconfdir}/rc0.d
	install -d ${D}${sysconfdir}/rc1.d
	install -d ${D}${sysconfdir}/rc2.d
	install -d ${D}${sysconfdir}/rc3.d
	install -d ${D}${sysconfdir}/rc4.d
	install -d ${D}${sysconfdir}/rc5.d
	install -d ${D}${sysconfdir}/rc6.d
	install -d ${D}${sysconfdir}/default
	install -d ${D}${sysconfdir}/default/volatiles
	# Holds state information pertaining to urandom
	install -d ${D}${localstatedir}/lib/urandom

	install -m 0644    ${WORKDIR}/functions		${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/bootmisc.sh	${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/hostname.sh	${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/rmnologin.sh	${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/sendsigs		${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/volatiles		${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/single		${D}${sysconfdir}/init.d
	install -m 0755    ${WORKDIR}/urandom		${D}${sysconfdir}/init.d
	sed -i ${D}${sysconfdir}/init.d/urandom -e 's,/var/,${localstatedir}/,g;s,/etc/,${sysconfdir}/,g'
	install -m 0755    ${WORKDIR}/dmesg.sh		${D}${sysconfdir}/init.d
	install -m 0644    ${WORKDIR}/logrotate-dmesg.conf ${D}${sysconfdir}/

#
# Install device dependent scripts
#
	install -m 0755 ${WORKDIR}/banner.sh	${D}${sysconfdir}/init.d/banner.sh
#
# Create runlevel links
#
	update-rc.d -r ${D} rmnologin.sh start 99 2 3 4 5 .
	update-rc.d -r ${D} sendsigs start 20 0 6 .
	update-rc.d -r ${D} urandom start 38 S 0 6 .
	update-rc.d -r ${D} banner.sh start 02 S .
	update-rc.d -r ${D} hostname.sh start 39 S .
	update-rc.d -r ${D} bootmisc.sh start 36 S .
 	# We wish to have /var/log ready at this stage so execute this after
	# populate-volatile.sh
	update-rc.d -r ${D} dmesg.sh start 38 S .
}

MASKED_SCRIPTS = " \
  banner \
  bootmisc \
  dmesg \
  hostname \
  rmnologin \
  volatiles \
  urandom"

pkg_postinst:${PN} () {
	if type systemctl >/dev/null 2>/dev/null; then
		if [ -n "$D" ]; then
			OPTS="--root=$D"
		fi
		for SERVICE in ${MASKED_SCRIPTS}; do
			systemctl $OPTS mask $SERVICE.service
		done
	fi

    # Delete any old volatile cache script, as directories may have moved
    if [ -z "$D" ]; then
        rm -f "/etc/volatile.cache"
    fi
}

CONFFILES:${PN} += "${sysconfdir}/init.d/checkroot.sh"

