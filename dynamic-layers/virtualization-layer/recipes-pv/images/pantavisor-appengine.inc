LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pantavisor-docker
inherit ${@bb.utils.contains_any('PANTAVISOR_FEATURES', 'pv-manifest-audit pv-manifest-strict', 'pv-manifest-audit', '', d)}

PV_MANIFEST_PREFIX = "pv-appengine"

FILESEXTRAPATHS:prepend := "${THISDIR}/pv-manifests:"

# Reference manifests for the upstream-supported MACHINE. The audit
# class only loads the one whose name matches the current
# PREFIX/MACHINE/DISTRO/CODENAME; the others sit unused in WORKDIR.
# Recipes that include this inc and produce a different rootfs (e.g.
# the tester variant) override PV_MANIFEST_PREFIX and append their own
# reference to SRC_URI.
SRC_URI += " \
    file://pv-appengine_panta-appengine-docker-x86_64-scarthgap.manifest.reference.txt \
"

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
	nftables \
	util-linux \
	pantavisor-pvtx \
	${@bb.utils.contains('PANTAVISOR_FEATURES', 'pvcontrol', 'pantavisor-pvcontrol', '', d)} \
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
