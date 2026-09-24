SUMMARY = "Pantavisor Avahi mDNS container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

IMAGE_BASENAME = "pv-avahi"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

IMAGE_INSTALL += "busybox avahi-daemon avahi-utils"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://args.json \
            file://config.json \
            file://pv-avahi-start.sh \
            file://ssh.service \
            file://pv-avahi-config \
            file://pv-avahi.services.json \
            file://avahi-policy.xml \
"

PV_CONFIG_OVERLAY_DIR = "pv-avahi-config"

PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
"

# app, not platform: pv-avahi is just a daemon in the host net namespace, and
# staying passive (status goal STAGED) until on-demand D-Bus activation
# starts it needs the app group's "container" restart policy so it can also
# be stopped/started manually via the containers API. args.json's PV_GROUP
# already said "app" (fix(pv-avahi): move container to app group /
# fix(pv-avahi): drop system restart policy), but this --group flag was
# never updated to match and silently overrode it at build time.
PVR_APP_ADD_GROUP = "app"

# Sign including config (override --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport

# Passive until on-demand D-Bus activation: PV_STATUS_GOAL STAGED in args.json.
# Ships the raw policy fragment narrowing the avahi-limited role.
pv_avahi_add_policy_fragment() {
    install -d ${PN}/dbus
    install -m 0644 ${WORKDIR}/avahi-policy.xml ${PN}/dbus/avahi-policy.xml
}
PVR_APP_POST_FIXUP = "pv_avahi_add_policy_fragment"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-avahi-start.sh ${IMAGE_ROOTFS}${bindir}/pv-avahi-start

    install -d ${IMAGE_ROOTFS}${sysconfdir}/avahi
    install -m 0644 ${WORKDIR}/pv-avahi-config/etc/avahi/avahi-daemon.conf ${IMAGE_ROOTFS}${sysconfdir}/avahi/avahi-daemon.conf

    install -d ${IMAGE_ROOTFS}${sysconfdir}/avahi/services
    install -m 0644 ${WORKDIR}/ssh.service ${IMAGE_ROOTFS}${sysconfdir}/avahi/services/ssh.service

    # Ensure runtime directories exist
    install -d ${IMAGE_ROOTFS}/run/avahi-daemon
    install -d ${IMAGE_ROOTFS}/var/run
}

# pv-avahi.services.json is picked up automatically by container-pvrexport
# (it copies ${PN}.services.json into the container's services.json), so no
# manual install into the rootfs is needed.

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "
