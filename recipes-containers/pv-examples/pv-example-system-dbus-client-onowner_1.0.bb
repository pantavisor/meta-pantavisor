SUMMARY = "Example hosted-bus D-Bus consumer, on-owner activated by org.freedesktop.Avahi"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-system-dbus-client-onowner"

PVRIMAGE_AUTO_MDEV = "0"

# Single-pid consumer: no dbus-daemon, just the client tools to dial the bus
# socket that pantavisor injects under the 'operator' role.
IMAGE_INSTALL += "dbus busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-dbus-client.sh \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-client.sh ${IMAGE_ROOTFS}${bindir}/pv-dbus-system-client
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-system-client"

# Passive until on-owner D-Bus activation; pvr's --status-goal MOUNTED drops
# type/config and skips the lxc.container.conf render, so fix it up after add.
pv_example_system_dbus_client_onowner_fixup_runjson() {
    jq '. + {"status_goal": "MOUNTED"}' ${PN}/run.json > ${PN}/run.json.tmp && mv ${PN}/run.json.tmp ${PN}/run.json
}
PVR_APP_POST_FIXUP = "pv_example_system_dbus_client_onowner_fixup_runjson"
