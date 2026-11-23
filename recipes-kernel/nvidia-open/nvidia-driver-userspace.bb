SUMMARY = "NVIDIA driver userspace for CUDA"
DESCRIPTION = "libcuda and the libraries it loads (PTX JIT, NVVM, GPU \
compiler), NVML and nvidia-smi, taken from the same driver release as the \
kernel modules. For GPU containers: there is no nvidia-container-toolkit to \
inject them from the host."

require nvidia-driver-run.inc

# For the shlib dependencies on glibc and libgcc_s (the CUDA debugger
# library); nothing is compiled.
DEPENDS = " \
	virtual/libc \
	libgcc \
"

NVIDIA_CUDA_LIBS = " \
	libcuda.so.${PV} \
	libnvidia-ptxjitcompiler.so.${PV} \
	libnvidia-nvvm.so.${PV} \
	libnvidia-nvvm70.so.4 \
	libnvidia-gpucomp.so.${PV} \
	libnvidia-ml.so.${PV} \
	libcudadebugger.so.${PV} \
"
NVIDIA_CUDA_BINS = " \
	nvidia-smi \
	nvidia-debugdump \
	nvidia-cuda-mps-control \
	nvidia-cuda-mps-server \
	nvidia-persistenced \
"
NVIDIA_RUN_MEMBERS = " \
	${NVIDIA_CUDA_LIBS} \
	${NVIDIA_CUDA_BINS} \
"

# Each library's SONAME link, as the installer's .manifest lists them. libcuda
# dlopens the JIT, NVVM and gpucomp by these names; gpucomp and nvvm70 are their
# own SONAME. The unversioned .so links go to -dev, for linking against libcuda.
do_install() {
	install -d ${D}${libdir} ${D}${bindir}
	for lib in ${NVIDIA_CUDA_LIBS}; do
		install -m 0755 ${S}/$lib ${D}${libdir}/
	done
	for bin in ${NVIDIA_CUDA_BINS}; do
		install -m 0755 ${S}/$bin ${D}${bindir}/
	done
	cd ${D}${libdir}
	ln -sf libcuda.so.${PV} libcuda.so.1
	ln -sf libcuda.so.1 libcuda.so
	ln -sf libnvidia-ptxjitcompiler.so.${PV} libnvidia-ptxjitcompiler.so.1
	ln -sf libnvidia-ptxjitcompiler.so.1 libnvidia-ptxjitcompiler.so
	ln -sf libnvidia-nvvm.so.${PV} libnvidia-nvvm.so.4
	ln -sf libnvidia-nvvm.so.4 libnvidia-nvvm.so
	ln -sf libnvidia-ml.so.${PV} libnvidia-ml.so.1
	ln -sf libnvidia-ml.so.1 libnvidia-ml.so
	ln -sf libcudadebugger.so.${PV} libcudadebugger.so.1
}

PACKAGES =+ " \
	${PN}-smi \
	${PN}-mps \
	${PN}-persistenced \
	${PN}-debugger \
"
FILES:${PN} = " \
	${libdir}/libcuda.so.* \
	${libdir}/libnvidia-ptxjitcompiler.so.* \
	${libdir}/libnvidia-nvvm.so.* \
	${libdir}/libnvidia-nvvm70.so.4 \
	${libdir}/libnvidia-gpucomp.so.* \
	${libdir}/libnvidia-ml.so.* \
"
FILES:${PN}-smi = " \
	${bindir}/nvidia-smi \
	${bindir}/nvidia-debugdump \
"
FILES:${PN}-mps = "${bindir}/nvidia-cuda-mps-*"
FILES:${PN}-persistenced = "${bindir}/nvidia-persistenced"
FILES:${PN}-debugger = "${libdir}/libcudadebugger.so.*"
FILES:${PN}-dev = "${libdir}/*.so"

# nvidia-smi dlopens NVML rather than linking it.
RDEPENDS:${PN}-smi = "${PN}"
RDEPENDS:${PN}-mps = "${PN}"
RDEPENDS:${PN}-debugger = "${PN}"

# libnvidia-gpucomp and libnvidia-nvvm70 carry the full version as SONAME,
# which the dev-so check takes for a development link.
INSANE_SKIP:${PN} = "already-stripped ldflags dev-so"
INSANE_SKIP:${PN}-smi = "already-stripped ldflags"
INSANE_SKIP:${PN}-mps = "already-stripped ldflags"
INSANE_SKIP:${PN}-persistenced = "already-stripped ldflags"
INSANE_SKIP:${PN}-debugger = "already-stripped ldflags"
