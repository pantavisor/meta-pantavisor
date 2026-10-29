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

# Unsloth itself needs PyTorch 2.x on CUDA 11.8+, which the Nano (sm_53,
# CUDA 10.2) cannot run: serve the repository's API with the standard
# library and the CUDA driver API instead of its FastAPI/torch server.py.
SRC_URI += "file://pv-unsloth-server.py file://pv-unsloth.args.json file://pv-unsloth.mdev.json"

PVRIMAGE_AUTO_MDEV = "0"
# Application group: a crash restarts this container, not the whole revision;
# after max_retries it is left stopped (backoff_policy never, args.json).
PVR_APP_ADD_GROUP = "app"
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/app/server.py"

install_unsloth_files() {
    install -d ${IMAGE_ROOTFS}/app
    install -d ${IMAGE_ROOTFS}/models
    install -m 0755 ${WORKDIR}/pv-unsloth-server.py ${IMAGE_ROOTFS}/app/server.py
}
ROOTFS_POSTPROCESS_COMMAND += "install_unsloth_files; "
