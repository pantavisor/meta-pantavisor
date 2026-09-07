SUMMARY = "Crust SCP firmware for Allwinner sunxi SoCs"
DESCRIPTION = "Libre firmware for the Allwinner AR100 System Control Processor (SCP). \
Implements the SCPI protocol TF-A's sun50i PSCI backend uses to reach deep suspend \
(PSCI SYSTEM_SUSPEND) on sun50i (A64/H5/H6) boards. Without it, TF-A falls back to a \
native PSCI backend that on H6 offers no deep suspend state, and Linux is limited to \
s2idle. See docs/overview/testing/testplans/testplan-wakelocks-opi3-crust.md."
HOMEPAGE = "https://github.com/crust-firmware/crust"
SECTION = "bsp"

LICENSE = "BSD-3-Clause | GPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE.md;md5=067c70adcecb42b71c442bd4bcde626c"

# One commit past the v0.6 tag: fixes a link failure ("undefined reference to
# __stack_chk_guard") seen with toolchains that enable the stack protector by
# default. crust has not tagged a release since; no newer fixes are being skipped.
SRC_URI = "git://github.com/crust-firmware/crust.git;branch=master;protocol=https"
SRCREV = "499a362645e6ce6ac1fd8ea8d0f25d4df6690688"
PV = "0.6+git"

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

DEPENDS = "gcc-or1k-elf-native binutils-or1k-elf-native flex-native bison-native"

COMPATIBLE_MACHINE = "orange-pi-3lts"

# No board-specific code is needed for basic crust functionality (upstream README):
# per-board defconfigs only pin the SoC platform + a couple of optional peripherals
# (IR receiver, PMIC MFD). orangepi_3_lts_defconfig does not exist upstream; verified
# the H6+AXP805 (MFD_AXP805 defaults to y for CONFIG_PLATFORM_H6) combination is
# identical to plain orangepi_3_defconfig, so this file is that defconfig, renamed
# and carried as a patch for clarity. Re-verify the CIR (IR receiver) line applies
# to the LTS variant once on hardware -- if not wired, it is a harmless no-op.
SRC_URI += "file://0001-add-orangepi_3_lts_defconfig.patch"

CRUST_DEFCONFIG = "orangepi_3_lts_defconfig"
CRUST_TARGET_SYS = "or1k-elf"

# GCC's -B self-location for its own assembler/linker only ever probes for
# the *unprefixed* tool name inside a "$(target)/bin/" dir (the classic
# binutils "tooldir" convention) -- never the target-prefixed name. That
# subdirectory doesn't survive OE's native sysroot staging (verified: even
# the entries binutils' own install creates there are gone by the time this
# recipe consumes the sysroot), so an unadorned or1k-elf-gcc silently falls
# back to plain $PATH "as"/"ld" -- the build host's own x86_64 assembler,
# which rejects every or1k instruction ("no such instruction: l.and ...").
# Recreate the tooldir locally from the prefixed binaries that DO stage
# correctly (usr/bin/or1k-elf-as etc, confirmed present), and point CC at it.
CRUST_TOOLDIR = "${WORKDIR}/${CRUST_TARGET_SYS}-tooldir"

EXTRA_OEMAKE = "\
    SRC=${S} \
    OBJ=${B} \
    TGT=${B}/scp \
    CROSS_COMPILE=${CRUST_TARGET_SYS}- \
    CC='${STAGING_BINDIR_NATIVE}/${CRUST_TARGET_SYS}-gcc -B${CRUST_TOOLDIR}/' \
    HOST_COMPILE= \
    HOSTCC='${BUILD_CC}' \
    LEX=flex \
    V=1 \
"

do_compile:prepend () {
    mkdir -p ${CRUST_TOOLDIR}
    for tool in as ld ld.bfd ar nm objcopy objdump ranlib strip readelf; do
        ln -sf ${STAGING_BINDIR_NATIVE}/${CRUST_TARGET_SYS}-${tool} ${CRUST_TOOLDIR}/${tool}
    done
}

do_configure () {
    oe_runmake -C ${S} ${CRUST_DEFCONFIG}
}
do_configure[cleandirs] = "${B}"

do_compile () {
    oe_runmake -C ${S} scp
}

do_install () {
    install -d ${D}/firmware
    install -m 0644 ${B}/scp/scp.bin ${D}/firmware/scp.bin
}

FILES:${PN} = "/firmware"
SYSROOT_DIRS += "/firmware"
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INSANE_SKIP:${PN} += "arch"

inherit deploy

do_deploy () {
    install -d ${DEPLOYDIR}
    install -m 0644 ${D}/firmware/scp.bin ${DEPLOYDIR}/scp.bin
}
addtask deploy after do_install
