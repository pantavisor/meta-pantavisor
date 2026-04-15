SUMMARY = "Pantavisor WiFi Connect container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pvwificonnect"

PVRIMAGE_AUTO_MDEV = "1"

IMAGE_FSTYPES = "pvrexportit"

IMAGE_INSTALL += "busybox pvwificonnect-app"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://args.json \
            file://config.json \
            file://pvwificonnect-config \
"

PV_CONFIG_OVERLAY_DIR = "pvwificonnect-config"

PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/tmp:permanent \
"

PVR_APP_ADD_GROUP = "platform"

# Sign including config (override --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# pvroot-image expects do_deploy to provide the .pvrexport.tgz
# do_image_complete sstate also deploys it, so use symlink to avoid conflict
fakeroot do_deploy() {
    :
}

addtask deploy after do_image_complete before do_build
