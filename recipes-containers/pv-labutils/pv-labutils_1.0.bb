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
IMAGE_INSTALL += "packagegroup-pv-labutils rsyslog"

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

# labutils points every facility at the console so lab output shows up in
# `pvcontrol logs`; left at the default, rsyslog writes into the container
# overlay where nothing reads it.
configure_rsyslog_console() {
    printf '\n# pv-labutils: mirror everything to the container console\n*.*\t/dev/console\n' \
        >> ${IMAGE_ROOTFS}${sysconfdir}/rsyslog.conf
}

ROOTFS_POSTPROCESS_COMMAND += "configure_rsyslog_console; "
