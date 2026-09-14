SUMMARY = "Pantacor lab controller utility container"
DESCRIPTION = "Board-control tooling for a Pantacor CI lab: USB and mains power \
switching, SD muxing, flashing (uuu/dfu-util/fastboot), serial consoles and pvr. \
Ports gitlab.com/pantacor/pv-platforms/labutils to a Yocto-built container."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-labutils"

# Board machine confs append their own rootfs types (sdimg, wic, ext4.gz) to
# every image; this one must only ever produce a pvrexport.
IMAGE_FSTYPES = "pvrexportit"

# core-image rather than `inherit image`: labutils runs OpenRC as /sbin/init,
# and packagegroup-core-boot's sysvinit is the equivalent that exists here.
# Set outright, not appended: core-image's default also carries
# packagegroup-base-extended, which on a board machine drags the machine's
# MACHINE_EXTRA_RRECOMMENDS (Wi-Fi/BT firmware, kernel modules) into a container.
IMAGE_INSTALL = "packagegroup-core-boot packagegroup-pv-labutils"
IMAGE_LINGUAS = ""

# No syslog daemon. labutils ran rsyslog only to mirror syslog() to the console,
# but rsyslog RCONFLICTS busybox-syslog, which this distro's busybox RPROVIDES
# (a stub for packagegroup-core-boot; trim.cfg removes the real syslogd applet),
# so it can never be installed here. The lab tools all write to stdout, which
# Pantavisor already captures into `pvcontrol logs`.

# core-image marks these noexec; SRC_URI needs them back.
do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-labutils.args.json"

# Permissive mdev: reaching USB hubs, SD muxes, DFU/fastboot endpoints and tty
# devices on the host is the entire point of this container. This plus the
# lxc.cgroup.devices.allow = a that every Pantavisor container already gets is
# the whole device-access story - no capability or cgroup tweaking needed
# (opi-gpio on the current lab controllers runs on exactly this).
PVRIMAGE_AUTO_MDEV = "1"

PVR_APP_ADD_GROUP = "platform"
# `+=` discards the class's ??= default, so /var is restated here rather than
# inherited: sysvinit and rsyslog need it writable.
PVR_APP_ADD_EXTRA_ARGS += " --config=Entrypoint=/sbin/init \
                            --volume ovl:/var:permanent \
                            --volume ovl:/tmp:permanent"

# Sign including config (override the --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport
