SUMMARY = "NVIDIA linux-nvidia kernel for DGX Spark (GB10)"
DESCRIPTION = "NVIDIA's Ubuntu kernel, which carries the GB10 enablement \
(ConnectX-7 and RTL8127 networking, CX7 PCIe hotplug, iGPU IOMMU quirks) that \
mainline does not have yet."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

# Kernel tag, commit and checksum come from conf/machine/include/dgx-os.inc,
# pinned to a DGX OS release. A tarball, because a git clone of NV-Kernels is
# several GB. Required here too because every machine parses this recipe, and
# an unset LINUX_VERSION breaks the linux bbappends' parsing elsewhere.
require conf/machine/include/dgx-os.inc
LINUX_VERSION = "${NV_KERNEL_LINUX_VERSION}"
# "Ubuntu-nvidia-7.0-7.0.0-1019.19_24.04.2" -> "1019.19"
PV = "${LINUX_VERSION}+nvidia${@d.getVar('NV_KERNEL_TAG').split('-')[-1].split('_')[0]}"

SRC_URI = " \
	https://github.com/NVIDIA/NV-Kernels/archive/${NV_KERNEL_SRCREV}.tar.gz;downloadfilename=nv-kernels-${NV_KERNEL_SRCREV}.tar.gz \
	file://defconfig \
	file://dgx-spark.cfg \
"
SRC_URI[sha256sum] = "${NV_KERNEL_SHA256}"

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
