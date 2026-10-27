SUMMARY = "Pantavisor Jetson CUDA runtime and GPU smoke test"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image container-pvrexport

COMPATIBLE_MACHINE = "^jetson-nano-devkit$"
IMAGE_INSTALL = "busybox cuda-samples tegra-libraries-cuda"
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "pvrexportit"
IMAGE_TYPES_MASKED:remove = "pvrexportit"
IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
NO_RECOMMENDATIONS = "1"

SRC_URI += "file://pv-jetson-cuda.args.json file://pv-jetson-cuda.mdev.json file://cuda-check"
PVRIMAGE_AUTO_MDEV = "0"
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/cuda-check"

install_cuda_check() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/cuda-check ${IMAGE_ROOTFS}${bindir}/cuda-check
}
ROOTFS_POSTPROCESS_COMMAND += "install_cuda_check; "
