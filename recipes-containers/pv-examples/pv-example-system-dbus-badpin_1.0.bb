SUMMARY = "Non-provider container pinning a role uid with no owns export — provokes a validation failure"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-system-dbus-badpin"

PVRIMAGE_AUTO_MDEV = "0"

# Deliberately minimal: this container never runs a real D-Bus server and owns
# no name. Its services.json only carries a top-level roles uid pin, so
# pv_dbus_policy_validate() rejects the state ("only a provider may pin a role
# uid") before any container runs — the revision errors and rolls back. A
# busybox sleep loop is all the payload we need.
IMAGE_INSTALL = "busybox"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-app.sh \
            file://${PN}.services.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-app.sh ${IMAGE_ROOTFS}${bindir}/pv-app
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-app"
