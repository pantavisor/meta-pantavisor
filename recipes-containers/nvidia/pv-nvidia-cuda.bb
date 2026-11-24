SUMMARY = "NVIDIA CUDA driver container for DGX Spark"
DESCRIPTION = "Checks the GPU with nvidia-smi and the CUDA driver API, using \
the CUDA driver userspace the BSP mounts at /usr/local/nvidia, the way a GPU \
application container does."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

COMPATIBLE_MACHINE = "dgx-spark"

IMAGE_BASENAME = "pv-nvidia-cuda"
IMAGE_FSTYPES = "pvrexportit"

IMAGE_INSTALL += " \
	busybox \
	base-files \
	base-passwd \
	pv-nvidia-utils \
"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += " \
	file://pv-nvidia-cuda.sh \
	file://pv-nvidia-cuda.args.json \
"

install_entrypoint() {
	install -d ${IMAGE_ROOTFS}${bindir}
	install -m 0755 ${WORKDIR}/pv-nvidia-cuda.sh ${IMAGE_ROOTFS}${bindir}/pv-nvidia-cuda
}
ROOTFS_POSTPROCESS_COMMAND += "install_entrypoint; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-nvidia-cuda"
