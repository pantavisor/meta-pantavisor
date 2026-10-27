SUMMARY = "Pantavisor Unsloth LLM and GPU runtime container"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit image container-pvrexport

COMPATIBLE_MACHINE = "^jetson-nano-devkit$"
IMAGE_INSTALL = "busybox python3 python3-core tegra-libraries-cuda ca-certificates base-files base-passwd"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "pvrexportit"
IMAGE_TYPES_MASKED:remove = "pvrexportit"
IMAGE_ROOTFS_SIZE = "16384"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
NO_RECOMMENDATIONS = "1"

PVPKG_DESCRIPTION ?= "Unsloth LLM fine-tuning and inference engine with GPU acceleration for Pantavisor."
PVPKG_PACKAGE_URL ?= "https://github.com/pantavisor/pv-unsloth"
PVPKG_URL ?= "${PVPKG_PACKAGE_URL}"

SRC_URI += "git://github.com/pantavisor/pv-unsloth.git;protocol=https;branch=main"
SRCREV = "31d989ba386bdddf42ed8555bc417576a29313a2"

PVRIMAGE_AUTO_MDEV = "0"
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/app/entrypoint.sh"

install_unsloth_files() {
    install -d ${IMAGE_ROOTFS}/app
    install -d ${IMAGE_ROOTFS}/models
    install -m 0755 ${WORKDIR}/git/entrypoint.sh ${IMAGE_ROOTFS}/app/entrypoint.sh
    install -m 0644 ${WORKDIR}/git/server.py ${IMAGE_ROOTFS}/app/server.py
    install -m 0644 ${WORKDIR}/git/mdev.json ${IMAGE_ROOTFS}/mdev.json
    install -m 0644 ${WORKDIR}/git/lxc.container.conf ${IMAGE_ROOTFS}/lxc.container.conf
}
ROOTFS_POSTPROCESS_COMMAND += "install_unsloth_files; "
