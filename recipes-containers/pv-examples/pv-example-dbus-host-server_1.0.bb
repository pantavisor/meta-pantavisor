SUMMARY = "Example hosted-bus D-Bus service (single-pid, owns a name on the pantavisor system bus)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-dbus-host-server"

PVRIMAGE_AUTO_MDEV = "0"

# Unlike the per-provider example, this container ships NO dbus-daemon, NO
# policy XML and NO /etc/passwd. The bus is hosted by pantavisor and the policy
# is generated from the owns declaration in services.json. The container only
# needs the client library to dial the injected bus socket and own its name.
IMAGE_INSTALL += "python3-core python3-pydbus python3-io busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-dbus-server.py \
            file://${PN}.services.json \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-dbus-server.py ${IMAGE_ROOTFS}${bindir}/pv-dbus-host-server
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-dbus-host-server"
