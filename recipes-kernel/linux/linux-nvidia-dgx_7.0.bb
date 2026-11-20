SUMMARY = "NVIDIA linux-nvidia kernel for DGX Spark (GB10)"
DESCRIPTION = "NVIDIA's Ubuntu kernel, which carries the GB10 enablement \
(ConnectX-7 and RTL8127 networking, CX7 PCIe hotplug, iGPU IOMMU quirks) that \
mainline does not have yet."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

# Tag Ubuntu-nvidia-7.0-7.0.0-1019.19_24.04.2, the DGX OS 7.6 kernel. Pin tag
# commits: NVIDIA rewrites the 24.04_linux-nvidia-*-next branches on every
# release. A tarball, because a git clone of NV-Kernels is several GB.
NV_KERNEL_SRCREV = "ae07646a606b3f18707246b0762464452cb40cbe"
LINUX_VERSION = "7.0.14"
PV = "${LINUX_VERSION}+nvidia1019.19"

SRC_URI = " \
	https://github.com/NVIDIA/NV-Kernels/archive/${NV_KERNEL_SRCREV}.tar.gz;downloadfilename=nv-kernels-${NV_KERNEL_SRCREV}.tar.gz \
	file://defconfig \
	file://dgx-spark.cfg \
"
SRC_URI[sha256sum] = "3b304fb138d12075c8abf5b7d3ba3ec7b582c8a64c3751b73a232c8bfc829853"

S = "${WORKDIR}/NV-Kernels-${NV_KERNEL_SRCREV}"

COMPATIBLE_MACHINE = "dgx-spark"

# Kernels since 6.12 install this; scarthgap's kernel.bbclass predates it.
FILES:${KERNEL_PACKAGE_NAME}-base:append = " ${nonarch_base_libdir}/modules/${KERNEL_VERSION}/modules.builtin.ranges"

# kernel.bbclass only copies defconfig; merge our fragment and the pantavisor
# ones from linux-%.bbappend on top before its olddefconfig.
do_configure:prepend() {
	cp ${WORKDIR}/defconfig ${B}/.config
	${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config \
		${WORKDIR}/dgx-spark.cfg \
		${KERNEL_CONFIG_FRAGMENTS}
}
