SUMMARY = "Example hosted-bus D-Bus consumer (single-pid, calls a name on the pantavisor system bus)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-host-client"

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
    install -m 0755 ${WORKDIR}/pv-dbus-client.sh ${IMAGE_ROOTFS}${bindir}/pv-dbus-host-client
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-host-client"
