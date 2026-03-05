SUMMARY = "DevicePass Hub for device fleet management"
DESCRIPTION = "Python hub service providing WebSocket tunnel for pv-devicepass \
device connections and REST API for guardian fleet management."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-devicepass-hub"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "python3-core python3-asyncio python3-json python3-io python3-pycryptodome python3-netclient busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://${PN}.py \
            file://${PN}.services.json \
            file://${PN}.args.json \
            file://${PN}.network.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/${PN}.py ${IMAGE_ROOTFS}${bindir}/pv-devicepass-hub
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-devicepass-hub"
