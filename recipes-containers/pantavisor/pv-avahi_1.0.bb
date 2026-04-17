SUMMARY = "Pantavisor Avahi mDNS container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

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
"

PV_CONFIG_OVERLAY_DIR = "pv-avahi-config"

PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
"

PVR_APP_ADD_GROUP = "platform"

# Sign including config (override --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# pvroot-image expects do_deploy to provide the .pvrexport.tgz
# do_image_complete sstate also deploys it, so use symlink to avoid conflict
fakeroot do_deploy() {
    :
}

addtask deploy after do_image_complete before do_build

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

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "