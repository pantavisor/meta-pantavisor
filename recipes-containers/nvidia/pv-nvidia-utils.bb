SUMMARY = "Pantavisor helpers for NVIDIA GPU containers"
DESCRIPTION = "cuda-probe runs the CUDA driver API on every GPU. \
/etc/dgx-os-release records the DGX OS release the container was built against."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

COMPATIBLE_MACHINE = "dgx-spark"
# Bakes the versions from dgx-os.inc, a machine setting.
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI = "file://cuda-probe.c"

S = "${WORKDIR}"

do_compile() {
	${CC} ${CFLAGS} ${LDFLAGS} -o cuda-probe cuda-probe.c -ldl
}

do_install() {
	install -d ${D}${bindir} ${D}${sysconfdir}
	install -m 0755 cuda-probe ${D}${bindir}/
	cat > ${D}${sysconfdir}/dgx-os-release <<EOF
DGX_OS_VERSION=${DGX_OS_VERSION}
DGX_OS_KERNEL_ABI=${DGX_OS_KERNEL_ABI}
NV_KERNEL_TAG=${NV_KERNEL_TAG}
NVIDIA_DRIVER_VERSION=${NVIDIA_DRIVER_VERSION}
DGX_OS_CUDA_VERSION=${DGX_OS_CUDA_VERSION}
EOF
}
do_install[vardeps] += " \
	DGX_OS_VERSION \
	DGX_OS_KERNEL_ABI \
	NV_KERNEL_TAG \
	NVIDIA_DRIVER_VERSION \
	DGX_OS_CUDA_VERSION \
"
