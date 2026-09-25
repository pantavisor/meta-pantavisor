SUMMARY = "Pantacor lab controller utility container"
DESCRIPTION = "Board-control tooling for a Pantacor CI lab: USB and mains power \
switching, SD muxing, flashing (uuu/dfu-util/fastboot), serial consoles and pvr. \
Ports gitlab.com/pantacor/pv-platforms/labutils to a Yocto-built container."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-labutils"

# Board machine confs append their own rootfs types (sdimg, wic, ext4.gz) to
# every image; this one must only ever produce a pvrexport.
IMAGE_FSTYPES = "pvrexportit"

# `inherit image` rather than core-image: it carries none of core-image's
# defaults, notably packagegroup-base-extended, which on a board machine
# drags the machine's MACHINE_EXTRA_RRECOMMENDS (Wi-Fi/BT firmware, kernel
# modules) into a container. What labutils lost from core-image is restated
# here: it runs sysvinit as /sbin/init (packagegroup-core-boot; the upstream
# apk platform boots OpenRC, sysvinit is the equivalent that exists here).
IMAGE_INSTALL = "packagegroup-core-boot packagegroup-pv-labutils"
IMAGE_LINGUAS = ""

# No syslog daemon. labutils ran rsyslog only to mirror syslog() to the console,
# but rsyslog RCONFLICTS busybox-syslog, which this distro's busybox RPROVIDES
# (a stub for packagegroup-core-boot; trim.cfg removes the real syslogd applet),
# so it can never be installed here. The lab tools all write to stdout, which
# Pantavisor already captures into `pvcontrol logs`.

# The image class marks these noexec; SRC_URI needs them back.
do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-labutils.args.json file://pv-gpio-set.sh file://pv-labutils.mdev.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-gpio-set.sh ${IMAGE_ROOTFS}${bindir}/pv-gpio-set
}

# base-files' `hostname:pn-base-files` default is `${MACHINE}`, but that
# override is scoped to the base-files recipe, which is shared by every
# image built for the same MACHINE - setting it there would rename every
# container built alongside this one, not just pv-labutils. Overwrite the
# already-installed /etc/hostname (and the matching /etc/hosts entry
# base-files wrote) here instead, so only this image gets a stable,
# machine-independent hostname.
set_hostname() {
    echo "${PN}" > ${IMAGE_ROOTFS}${sysconfdir}/hostname
    sed -i "s/^127.0.1.1.*/127.0.1.1 ${PN}/" ${IMAGE_ROOTFS}${sysconfdir}/hosts
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; set_hostname; "

# Permissive mdev (files/pv-labutils.mdev.json, picked up over the
# PVRIMAGE_AUTO_MDEV default because container-pvrexport prefers an explicit
# ${PN}.mdev.json when one is in SRC_URI): reaching USB hubs, SD muxes,
# DFU/fastboot endpoints, GPIO chips and tty devices on the host is the entire
# point of this container. This plus the lxc.cgroup.devices.allow = a that
# every Pantavisor container already gets is the whole device-access story -
# no capability or cgroup tweaking needed (opi-gpio on the current lab
# controllers runs on exactly this). Add narrower rules to that file first
# (mdev rule syntax: "<regex> <uid>:<gid> <mode>") if a tighter policy is ever
# needed; the wildcard stays first-match unless reordered.

PVR_APP_ADD_GROUP = "platform"
# `+=` discards the class's ??= default, so /var is restated here rather than
# inherited: sysvinit needs /var/run and /var/lock writable.
PVR_APP_ADD_EXTRA_ARGS += " --config=Entrypoint=/sbin/init \
                            --volume ovl:/var:permanent \
                            --volume ovl:/tmp:permanent"

# Sign including config (override the --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport
