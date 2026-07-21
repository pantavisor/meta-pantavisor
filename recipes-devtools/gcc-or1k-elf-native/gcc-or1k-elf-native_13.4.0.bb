SUMMARY = "GNU C compiler for the or1k-elf freestanding target"
DESCRIPTION = "Bare-metal or1k-elf C compiler (stage-1: C-only, no target libc/newlib), \
used only to build the crust SCP firmware (recipes-bsp/crust) for Allwinner sun50i (H6) \
boards. or1k gained upstream GCC support in 9.1.0; this recipe uses the same GCC release \
(13.4.0) already built elsewhere in this layer for other native/cross toolchains. Not a \
target toolchain: or1k is unrelated to any MACHINE built by this layer."
HOMEPAGE = "https://gcc.gnu.org/"
SECTION = "devel"

LICENSE = "GPL-3.0-with-GCC-exception & GPL-3.0-only"
LIC_FILES_CHKSUM = "\
    file://COPYING;md5=59530bdf33659b29e73d4adb9f9f6552 \
    file://COPYING3;md5=d32239bcb673463ab874e80d47fae504 \
    file://COPYING3.LIB;md5=6a6a8e020838b23406c81b19c1d46df6 \
    file://COPYING.RUNTIME;md5=fe60d87048567d4fe8c8a0ed2448bcc8 \
"

inherit native

SRC_URI = "${GNU_MIRROR}/gcc/gcc-${PV}/gcc-${PV}.tar.xz"
SRC_URI[sha256sum] = "9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5"

S = "${WORKDIR}/gcc-${PV}"
B = "${WORKDIR}/build-or1k-elf"

DEPENDS = "binutils-or1k-elf-native gmp-native mpfr-native libmpc-native"

CRUST_TARGET_SYS = "or1k-elf"

# OE exports CC/CFLAGS/CPPFLAGS/LDFLAGS etc for every native recipe (pointing
# at the host build compiler and the shared native staging sysroot, so plain
# native tools find their -native DEPENDS without extra flags). libgcc's own
# sub-configure (invoked recursively during "all-target-libgcc", one per
# multilib variant) inherits environment CC in preference to the CC_FOR_TARGET
# gcc's top-level Makefile passes it -- so its AC_CHECK_HEADERS(sys/mman.h)
# ran against the HOST gcc, found the host's real header, and baked
# HAVE_SYS_MMAN_H=1 into config.h; the actual target xgcc compile of that file
# then fails since --without-headers correctly gives it no such header. Same
# story for CPPFLAGS ("-isystem${STAGING_INCDIR_NATIVE}" leaking past
# --without-headers) and CFLAGS/LDFLAGS (breaks GCC's own host-side bootstrap,
# reproduced standalone outside bitbake before landing this). This recipe
# manages its own flags/tools end to end, so don't export any of these.
CC[unexport] = "1"
CXX[unexport] = "1"
CPP[unexport] = "1"
AS[unexport] = "1"
LD[unexport] = "1"
AR[unexport] = "1"
NM[unexport] = "1"
RANLIB[unexport] = "1"
STRIP[unexport] = "1"
OBJCOPY[unexport] = "1"
OBJDUMP[unexport] = "1"
CPPFLAGS[unexport] = "1"
CFLAGS[unexport] = "1"
CXXFLAGS[unexport] = "1"
LDFLAGS[unexport] = "1"

# Stage-1 freestanding compiler: C only, no target libc. crust does not call any
# libc functions (it is freestanding firmware); it only needs libgcc for compiler
# helper routines. Multilib is intentionally left enabled (not --disable-multilib)
# so libgcc is built for the msoft-mul/msoft-div variant crust's arch/or1k/Makefile
# selects, alongside the hard-mul/hard-div/mcmov default.
do_configure () {
    ${S}/configure \
        --target=${CRUST_TARGET_SYS} \
        --prefix=${prefix} \
        --disable-nls \
        --disable-shared \
        --disable-threads \
        --enable-languages=c \
        --without-headers \
        --disable-decimal-float \
        --disable-libffi \
        --disable-libgomp \
        --disable-libmudflap \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libatomic \
        --disable-libitm \
        --disable-libsanitizer \
        --disable-libvtv \
        --disable-libstdcxx \
        --disable-bootstrap \
        --disable-werror \
        --with-gnu-as \
        --with-gnu-ld \
        --with-gmp=${prefix} \
        --with-mpfr=${prefix} \
        --with-mpc=${prefix}
}
do_configure[cleandirs] = "${B}"

do_compile () {
    # all-gcc builds host-side helpers (e.g. gcc/config/host-linux.cc) that
    # run on and legitimately need the *build* machine's real sys/mman.h
    # (PCH memory-mapping) -- do NOT touch HAVE_SYS_MMAN_H detection here.
    oe_runmake all-gcc

    # libgcc's own recursive sub-configure (one per multilib variant)
    # autodetects HAVE_SYS_MMAN_H by probing whatever CC it ends up
    # resolving for that check -- which, depending on environment, may not
    # be the real freestanding target compiler. A truly headerless or1k-elf
    # target has no sys/mman.h by definition; force the answer via
    # autoconf's documented cache-variable-as-env-override convention,
    # scoped to just this step so it can't affect all-gcc above.
    ac_cv_header_sys_mman_h=no oe_runmake all-target-libgcc
}

do_install () {
    oe_runmake install-gcc install-target-libgcc DESTDIR=${D}
}

BBCLASSEXTEND = ""
