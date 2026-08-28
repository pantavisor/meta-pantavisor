SUMMARY = "GNU binutils for the or1k-elf freestanding target"
DESCRIPTION = "Bare-metal or1k-elf assembler/linker, used only to build the crust \
SCP firmware (recipes-bsp/crust) for Allwinner sun50i (H6) boards. Not a target \
toolchain: or1k is unrelated to any MACHINE built by this layer."
HOMEPAGE = "https://www.gnu.org/software/binutils/"
SECTION = "devel"

LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "\
    file://COPYING;md5=59530bdf33659b29e73d4adb9f9f6552 \
    file://COPYING3;md5=d32239bcb673463ab874e80d47fae504 \
"

inherit native

SRC_URI = "${GNU_MIRROR}/binutils/binutils-${PV}.tar.xz"
SRC_URI[sha256sum] = "f6e4d41fd5fc778b06b7891457b3620da5ecea1006c6a4a41ae998109f85a800"

S = "${WORKDIR}/binutils-${PV}"
B = "${WORKDIR}/build-or1k-elf"

DEPENDS = "bison-native flex-native"

CRUST_TARGET_SYS = "or1k-elf"

# See gcc-or1k-elf-native for why: OE's native CPPFLAGS/CFLAGS/LDFLAGS point at
# the shared native staging sysroot, which has no business leaking into a
# from-scratch freestanding-target toolchain build.
CPPFLAGS[unexport] = "1"
CFLAGS[unexport] = "1"
CXXFLAGS[unexport] = "1"
LDFLAGS[unexport] = "1"

do_configure () {
    ${S}/configure \
        --target=${CRUST_TARGET_SYS} \
        --prefix=${prefix} \
        --disable-nls \
        --disable-werror \
        --disable-gdb \
        --disable-sim \
        --disable-libdecnumber \
        --disable-readline \
        --without-zstd
}

do_compile () {
    oe_runmake
}

do_install () {
    oe_runmake install DESTDIR=${D}
}

# binutils' own install DOES create an unprefixed $target/bin/ "tooldir" (used
# by GCC's -B self-location for as/ld -- see gcc-or1k-elf-native and
# crust-firmware for why that matters) for most tools, but that whole
# subdirectory does not survive OE's native sysroot staging into consuming
# recipes for reasons not worth fighting further -- confirmed even the
# entries binutils' Makefile itself creates (nm, ar, ...) are gone from
# crust-firmware's merged recipe-sysroot-native. crust-firmware recreates
# this tooldir itself, locally, from the prefixed binaries that DO stage
# correctly, instead of depending on this recipe's install output for it.

BBCLASSEXTEND = ""
