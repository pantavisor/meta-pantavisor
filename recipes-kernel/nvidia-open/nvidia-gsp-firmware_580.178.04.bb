SUMMARY = "NVIDIA GSP firmware"
DESCRIPTION = "Firmware for the GPU System Processor, which the open kernel \
modules boot when they probe the GPU. It is tied to the driver release."
HOMEPAGE = "https://www.nvidia.com/en-us/drivers/"
LICENSE = "NVIDIA-Driver"
NO_GENERIC_LICENSE[NVIDIA-Driver] = "LICENSE"
LIC_FILES_CHKSUM = "file://LICENSE;md5=92aa2e2af6aa0bcba1c3fe49da021937"
# Proprietary; accept with LICENSE_FLAGS_ACCEPTED += "nvidia-driver".
LICENSE_FLAGS = "nvidia-driver"

require nvidia-open.inc

SRC_URI = "https://download.nvidia.com/XFree86/Linux-aarch64/${PV}/NVIDIA-Linux-aarch64-${PV}.run;unpack=0"
SRC_URI[sha256sum] = "ef59ec5d24850e12d6f7550ec1f7cf84db53a84ce9c63eb3ba55ef5ed0c4f049"

S = "${WORKDIR}/NVIDIA-Linux-aarch64-${PV}"

python () {
    if d.getVar('PV') != d.getVar('NVIDIA_DRIVER_VERSION'):
        raise bb.parse.SkipRecipe('PV must equal NVIDIA_DRIVER_VERSION')
}

# The .run is a makeself archive: a shell header (skip= on line 4 of the file)
# followed by a zstd tar. Unpack the payload directly instead of running the
# installer; it has to happen in do_unpack, before the license check.
nvidia_run_extract() {
	run=${WORKDIR}/NVIDIA-Linux-aarch64-${PV}.run
	skip=$(sed -n '1,20s/^skip=\([0-9]*\)$/\1/p' $run)
	[ -n "$skip" ] || bbfatal "no skip= in the header of $run"
	rm -rf ${S}
	mkdir -p ${S}
	tail -n +$skip $run | zstd -dc | tar -xf - -C ${S} LICENSE firmware
}
do_unpack[postfuncs] += "nvidia_run_extract"

INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"

# GB10 (GB10X/GB10Y) and every other GA10x-and-later chip load gsp_ga10x;
# gsp_tu10x is only for Turing and GA100.
do_install() {
	install -d ${D}${nonarch_base_libdir}/firmware/nvidia/${PV}
	install -m 0644 ${S}/firmware/gsp_ga10x.bin \
		${D}${nonarch_base_libdir}/firmware/nvidia/${PV}/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware/nvidia"

# The blob is a RISC-V ELF for the GSP, not for the host CPU.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP:${PN} = "arch already-stripped"
PACKAGE_ARCH = "${MACHINE_ARCH}"
