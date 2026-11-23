# NVIDIA's aarch64 .run installer, for recipes that take prebuilt parts of the
# driver release out of it. Set NVIDIA_RUN_MEMBERS to what they need.
HOMEPAGE = "https://www.nvidia.com/en-us/drivers/"
LICENSE = "NVIDIA-Driver"
NO_GENERIC_LICENSE[NVIDIA-Driver] = "LICENSE"
LIC_FILES_CHKSUM = "file://LICENSE;md5=92aa2e2af6aa0bcba1c3fe49da021937"
# Proprietary; accept with LICENSE_FLAGS_ACCEPTED += "nvidia-driver".
LICENSE_FLAGS = "nvidia-driver"

require nvidia-open.inc

SRC_URI = "https://download.nvidia.com/XFree86/Linux-aarch64/${PV}/NVIDIA-Linux-aarch64-${PV}.run;unpack=0"
SRC_URI[sha256sum] = "${NVIDIA_DRIVER_RUN_SHA256}"

S = "${WORKDIR}/NVIDIA-Linux-aarch64-${PV}"

NVIDIA_RUN_MEMBERS ?= ""

# The .run is a makeself archive: a shell header (skip= on line 4 of the file)
# followed by a zstd tar. Unpack the payload directly instead of running the
# installer; it has to happen in do_unpack, before the license check.
nvidia_run_extract() {
	run=${WORKDIR}/NVIDIA-Linux-aarch64-${PV}.run
	skip=$(sed -n '1,20s/^skip=\([0-9]*\)$/\1/p' $run)
	[ -n "$skip" ] || bbfatal "no skip= in the header of $run"
	rm -rf ${S}
	mkdir -p ${S}
	tail -n +$skip $run | zstd -dc | tar -xf - -C ${S} LICENSE ${NVIDIA_RUN_MEMBERS}
}
do_unpack[postfuncs] += "nvidia_run_extract"
do_unpack[vardeps] += "NVIDIA_RUN_MEMBERS"

INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"

# Prebuilt and already stripped; the GSP blob is not even a host binary.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_SYSROOT_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
# The release is a machine setting (dgx-os.inc), so is everything built from it.
PACKAGE_ARCH = "${MACHINE_ARCH}"
