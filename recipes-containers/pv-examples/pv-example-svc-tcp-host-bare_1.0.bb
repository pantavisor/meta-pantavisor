SUMMARY = "Negative test fixture (TC-11): host-mode xconnect service participant without lxc.net.*"
DESCRIPTION = "Declares network.mode=host (via .network.json injection) and exports a TCP service, but ships no lxc.net.* in its lxc.container.conf. Pantavisor must refuse the start: host-net service participants must bring their own network config."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-svc-tcp-host-bare"

PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-example-svc-tcp-provider.sh \
            file://${PN}.services.json \
            file://${PN}.network.json \
            file://${PN}.args.json"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-example-svc-tcp-provider.sh ${IMAGE_ROOTFS}${bindir}/pv-example-svc-tcp-host-bare

    install -m 0644 ${WORKDIR}/${PN}.services.json ${IMAGE_ROOTFS}/services.json
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-example-svc-tcp-host-bare"
