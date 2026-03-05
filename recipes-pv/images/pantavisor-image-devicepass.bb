SUMMARY = "Pantavisor DevicePass Appengine Image"
DESCRIPTION = "Appengine image with devicepass containers pre-installed in pvtx.d: \
device identity, hub, anvil testnet, and IPAM networking."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

DOCKER_IMAGE_NAME = "pantavisor-image-devicepass"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

# Devicepass containers to bake into pvtx.d
DEVICEPASS_CONTAINERS = " \
    pv-devicepass-container \
    pv-devicepass-hub \
    pv-devicepass-anvil \
    pv-example-device-config-proxy \
"

# Ensure container pvrexports are built before our image
do_rootfs[depends] += " \
    pv-devicepass-container:do_deploy \
    pv-devicepass-hub:do_deploy \
    pv-devicepass-anvil:do_deploy \
    pv-example-device-config-proxy:do_deploy \
"

install_devicepass_containers() {
    install -d ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d
    for c in ${DEVICEPASS_CONTAINERS}; do
        if [ -f ${DEPLOY_DIR_IMAGE}/${c}.pvrexport.tgz ]; then
            install -m 0644 ${DEPLOY_DIR_IMAGE}/${c}.pvrexport.tgz \
                ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d/
        else
            bbwarn "Missing pvrexport: ${c}.pvrexport.tgz"
        fi
    done
}

ROOTFS_POSTPROCESS_COMMAND += "install_devicepass_containers; "
