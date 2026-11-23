SUMMARY = "NVIDIA open GPU kernel modules"
DESCRIPTION = "nvidia, nvidia-uvm, nvidia-modeset, nvidia-drm and nvidia-peermem \
built from NVIDIA's open kernel module source. Blackwell GPUs, GB10 included, \
are only supported by the open modules."
HOMEPAGE = "https://github.com/NVIDIA/open-gpu-kernel-modules"
LICENSE = "MIT & GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=1d5fa2a493e937d5a4b96e5e03b90f7c"

require nvidia-open.inc
inherit module

SRC_URI = "https://github.com/NVIDIA/open-gpu-kernel-modules/archive/refs/tags/${PV}.tar.gz;downloadfilename=open-gpu-kernel-modules-${PV}.tar.gz"
SRC_URI[sha256sum] = "${NVIDIA_OPEN_SHA256}"

S = "${WORKDIR}/open-gpu-kernel-modules-${PV}"

# The top-level Makefile first builds the OS-agnostic cores (nv-kernel.o,
# nv-modeset-kernel.o) with plain CC/CXX, then kbuilds kernel-open/ around them.
EXTRA_OEMAKE = " \
	TARGET_ARCH=aarch64 \
	ARCH=arm64 \
	SYSSRC=${STAGING_KERNEL_DIR} \
	SYSOUT=${STAGING_KERNEL_BUILDDIR} \
	KERNEL_UNAME=${KERNEL_VERSION} \
	CC='${KERNEL_CC}' \
	CXX='${HOST_PREFIX}g++' \
	LD='${KERNEL_LD}' \
	AR='${KERNEL_AR}' \
	OBJCOPY='${KERNEL_OBJCOPY}' \
	NV_VERBOSE=1 \
"

do_compile() {
	unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
	oe_runmake modules
}

do_install() {
	install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/video
	install -m 0644 ${S}/kernel-open/*.ko \
		${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/drivers/video/
}

RRECOMMENDS:${PN} += "nvidia-gsp-firmware"
