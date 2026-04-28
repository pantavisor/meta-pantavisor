
# meta-pantavisor/dynamic-layers/meta-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend
#
# Enable CONFIG_COMPAT_VDSO=y for arm64 kernels by exposing a 32-bit
# ARM cross-toolchain (gcc + binutils) to Kbuild via PATH +
# CROSS_COMPILE_COMPAT.
#
# Background: arch/arm64/Kconfig defines COMPAT_VDSO as default-y, but
# only if either (CC_IS_CLANG && LD_IS_LLD) or CROSS_COMPILE_COMPAT is
# set. With gcc + bfd (Yocto's default), CROSS_COMPILE_COMPAT must be
# provided explicitly, otherwise the compat vDSO is silently dropped
# from the build.
#
# Without the compat vDSO, 32-bit userspace processes (e.g. Go binaries
# built for linux/arm/v6) running on a 64-bit kernel fall back to the
# raw clock_gettime syscall path, which has historically had
# regressions on arm64 compat (Go runtime startup wedges, futex_time64
# issues, etc.). Providing the compat vDSO matches what stock distro
# arm64 kernels (Debian, Ubuntu, Arch) ship.

# The cross-toolchain triplet's libc suffix depends on the distro's
# C library (musl vs glibc). Pantavisor builds against musl, so the
# arm32 cross-toolchain is `arm-poky-linux-musleabi-`. On a glibc
# distro it would be `arm-poky-linux-gnueabi-`.
COMPAT_LIBC_SUFFIX = "${@'musleabi' if d.getVar('TCLIBC') == 'musl' else 'gnueabi'}"
COMPAT_TRIPLET = "arm${TARGET_VENDOR}-linux-${COMPAT_LIBC_SUFFIX}"

# The 32-bit ARM cross-gcc and cross-binutils are produced by the
# rpi-kernel multiconfig (MACHINE=raspberrypi). Each multiconfig has
# an isolated `recipe-sysroot-native`, so the arm64 kernel build
# can't see the v6 multiconfig's binaries on PATH by default. Add
# both component bin dirs to PATH at compile time so Kbuild's
# vdso32 step can find arm-poky-linux-musleabi-{gcc,as,ld,...}.
COMPAT_GCC_BIN_DIR  = "${TOPDIR}/tmp-${DISTRO_CODENAME}-rpi-kernel-raspberrypi/sysroots-components/${BUILD_ARCH}/gcc-cross-arm/usr/bin/${COMPAT_TRIPLET}"
COMPAT_BUTILS_BIN_DIR = "${TOPDIR}/tmp-${DISTRO_CODENAME}-rpi-kernel-raspberrypi/sysroots-components/${BUILD_ARCH}/binutils-cross-arm/usr/bin/${COMPAT_TRIPLET}"

EXTRA_OEMAKE:append:aarch64 = " CROSS_COMPILE_COMPAT=${COMPAT_TRIPLET}-"

# Build a shim directory under the kernel's WORKDIR with un-prefixed
# symlinks (`as`, `ld`, `objcopy`, `objdump`, `gcc`, `cpp`, `nm`, `ar`,
# `ranlib`, `strip`) pointing at the v6 multiconfig's prefixed cross-
# binaries. Without this, gcc's internal assembler invocation finds
# the host /usr/bin/as ("as: unrecognized option '-EL'") because the
# Yocto cross-gcc package doesn't ship `as` in its libexec — it
# expects PATH to provide either the prefixed or un-prefixed name,
# and Kbuild's vdso32 rules end up calling plain `as` directly.
COMPAT_SHIM_DIR = "${WORKDIR}/compat-toolchain-shim"

setup_compat_toolchain_shim () {
    install -d ${COMPAT_SHIM_DIR}
    for tool in as ld objcopy objdump nm ar ranlib strip cpp; do
        ln -sf "${COMPAT_BUTILS_BIN_DIR}/${COMPAT_TRIPLET}-$tool" \
            "${COMPAT_SHIM_DIR}/$tool"
    done
    for tool in gcc g++ cpp; do
        ln -sf "${COMPAT_GCC_BIN_DIR}/${COMPAT_TRIPLET}-$tool" \
            "${COMPAT_SHIM_DIR}/$tool" 2>/dev/null || true
    done
    export PATH="${COMPAT_SHIM_DIR}:${COMPAT_GCC_BIN_DIR}:${COMPAT_BUTILS_BIN_DIR}:${PATH}"
}

# Both `do_compile` (vmlinux) AND `do_compile_kernelmodules` (in-tree
# modules) run vdso_prepare, so both need the shim + PATH applied.
# Without the second one, `do_compile_kernelmodules` re-fails on
# `arm-poky-linux-musleabi-gcc: not found` even after a successful
# `do_compile`.
do_compile:prepend:aarch64 () {
    setup_compat_toolchain_shim
}
do_compile_kernelmodules:prepend:aarch64 () {
    setup_compat_toolchain_shim
}

# Make do_compile wait until the rpi-kernel multiconfig has populated
# both gcc-cross-arm and binutils-cross-arm sysroots — without these
# mcdepends, the arm64 kernel may run vdso32 compile before the path
# above is populated. mcdepends crosses the per-multiconfig boundary
# that ordinary DEPENDS cannot.
do_compile[mcdepends] += "mc::rpi-kernel:gcc-cross-arm:do_populate_sysroot \
                          mc::rpi-kernel:binutils-cross-arm:do_populate_sysroot"
