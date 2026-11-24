SUMMARY = "NVIDIA GSP firmware"
DESCRIPTION = "Firmware for the GPU System Processor, which the open kernel \
modules boot when they probe the GPU. It is tied to the driver release."

require nvidia-driver-run.inc

NVIDIA_RUN_MEMBERS = "firmware"

# GB10 (GB10X/GB10Y) and every other GA10x-and-later chip load gsp_ga10x;
# gsp_tu10x is only for Turing and GA100.
do_install() {
	install -d ${D}${nonarch_base_libdir}/firmware/nvidia/${PV}
	install -m 0644 ${S}/firmware/gsp_ga10x.bin \
		${D}${nonarch_base_libdir}/firmware/nvidia/${PV}/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware/nvidia"

# The blob is a RISC-V ELF for the GSP, not for the host CPU.
INSANE_SKIP:${PN} = "arch already-stripped"
