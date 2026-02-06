LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pantavisor-docker

DOCKER_IMAGE_NAME = "${PN}"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

CORE_IMAGE_EXTRA_INSTALL += " \
        bash \
	dnsmasq \
	hostapd \
	iw \
"

SRC_URI += " \
	file://pv-netsim_hostapd.conf \
	file://pv-netsim_run-netsim.sh \
"


do_install_scripts() {

    echo "Starting Install of appengine netsim"

    mkdir -p ${IMAGE_ROOTFS}/etc/hostapd
    install -m 0644 ${WORKDIR}/pv-netsim_hostapd.conf ${IMAGE_ROOTFS}/etc/hostapd/hostapd.conf

    mkdir -p ${IMAGE_ROOTFS}/usr/local/bin
    install -m 0755 ${WORKDIR}/pv-netsim_run-netsim.sh ${IMAGE_ROOTFS}/usr/local/bin/pv-netsim_run

}

PV_DOCKER_IMAGE_ENTRYPOINT_ARGS = '-c "/usr/local/bin/pv-netsim_run $VERBOSE"'
PV_DOCKER_IMAGE_ENVS = 'VERBOSE=""'

ROOTFS_POSTPROCESS_COMMAND += "do_install_scripts"

