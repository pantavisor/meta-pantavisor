SUMMARY = "Example hosted-bus D-Bus consumer with a non-allowed role (denied by generated policy)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-system-dbus-client-denied"

PVRIMAGE_AUTO_MDEV = "0"

# Single-pid consumer identical to pv-example-system-dbus-client, but it dials
# the bus under the 'stranger' role, which is NOT in the server's allow list.
# The generated default-deny policy grants its masqueraded uid no send access to
# the owned name, so its calls are refused — proving the allow list restricts
# callers rather than merely permitting the listed ones.
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
