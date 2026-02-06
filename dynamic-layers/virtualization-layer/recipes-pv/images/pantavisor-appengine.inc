LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pantavisor-docker

DOCKER_IMAGE_NAME = "pantavisor-appengine"
DOCKER_IMAGE_TAG = "1.0"

VIRTUAL-RUNTIME_pantavisor_config ?= "pantavisor-config"

CORE_IMAGE_EXTRA_INSTALL += " \
	coreutils \
	pantavisor \
	bash \
	dnsmasq \
	hostapd \
	iw \
	util-linux \
	pantavisor-pvtx \
	pvcontrol \
	${VIRTUAL-RUNTIME_pantavisor_config} \
"


SRC_URI += " \
"

do_install_scripts() {

    echo "Starting Install of appengine scripts"

    # Copy the file from the Yocto work directory (${WORKDIR}) to the destination
    find ${IMAGE_ROOTFS}/ -type f
    if ! [ -f ${IMAGE_ROOTFS}/etc/pantavisor/defaults/groups.json ]; then
	echo "ERROR NO GROUPS"
	exit 2
    fi

}

OCI_IMAGE_ENTRYPOINT_ARGS = "/usr/bin/pv-appengine"

ROOTFS_POSTPROCESS_COMMAND += "do_install_scripts"

