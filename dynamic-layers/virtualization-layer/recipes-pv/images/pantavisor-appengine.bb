LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

CORE_IMAGE_EXTRA_INSTALL:append = " valgrind"

DOCKER_IMAGE_NAME = "pantavisor-appengine"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

# Bake the BSP pvrexport tarball into pvtx.d so pv-appengine can run pvtx
# on first boot without needing the tarball injected at test run time.
# Run as a separate task after do_rootfs (not as a ROOTFS_POSTPROCESS_COMMAND)
# so its [depends] on pantavisor-bsp does not trigger Yocto's package integrity
# check for pvrexport recipes that mark package_write_rpm as noexec.
do_install_bsp_pvtx[depends] = "pantavisor-bsp:do_compile"
do_install_bsp_pvtx() {
    install -d ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d
    bsp_tgz=""
    for f in ${DEPLOY_DIR_IMAGE}/pantavisor-bsp-${MACHINE}.pvrexport.tgz; do
        [ -e "$f" ] && bsp_tgz="$f" && break
    done
    if [ -z "$bsp_tgz" ]; then
        bbfatal "pantavisor-appengine: BSP tarball not found in ${DEPLOY_DIR_IMAGE}"
    fi
    install -m 644 "$bsp_tgz" ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d/bsp.tgz
}
addtask install_bsp_pvtx after do_rootfs before do_image

do_install_pvr_sdk_pvtx[depends] = "pv-pvr-sdk:do_deploy"
do_install_pvr_sdk_pvtx() {
    install -d ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d
    pvr_sdk_tgz=""
    for f in ${DEPLOY_DIR_IMAGE}/pv-pvr-sdk.pvrexport.tgz ${DEPLOY_DIR_IMAGE}/pv-pvr-sdk-*.pvrexport.tgz; do
        [ -e "$f" ] && pvr_sdk_tgz="$f" && break
    done
    if [ -z "$pvr_sdk_tgz" ]; then
        bbfatal "pantavisor-appengine: pvr-sdk tarball not found in ${DEPLOY_DIR_IMAGE}"
    fi
    install -m 644 "$pvr_sdk_tgz" ${IMAGE_ROOTFS}/usr/lib/pantavisor/pvtx.d/pvr-sdk.tgz
}
addtask install_pvr_sdk_pvtx after do_rootfs before do_image

