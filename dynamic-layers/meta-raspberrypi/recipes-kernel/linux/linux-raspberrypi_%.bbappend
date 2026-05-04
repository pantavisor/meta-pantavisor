
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
#
# The 32-bit ARM cross-toolchain only exists inside the rpi-kernel
# multiconfig's sysroots-components tree, which is only built when
# the unified rpi-tryboot configuration enables BBMULTICONFIG (e.g.
# kas/build-configs/release/rpi-scarthgap.yaml). Pure single-arch
# builds like raspberrypi-armv8-scarthgap.yaml do NOT enable that
# multiconfig, so referencing mc::rpi-kernel:... unconditionally
# would break parsing with:
#   "Multiconfig 'rpi-kernel' is referenced in multiconfig dependency
#    ... but not enabled in BBMULTICONFIG?"
#
# Therefore the entire compat-vDSO setup (mcdepends, EXTRA_OEMAKE,
# the PATH shim) is gated on rpi-kernel actually being part of
# BBMULTICONFIG. On a non-multiconfig arm64 build this bbappend is
# a no-op.

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

COMPAT_SHIM_DIR = "${WORKDIR}/compat-toolchain-shim"

# Sentinel: only "1" when the rpi-kernel multiconfig is enabled and
# this kernel is being built for aarch64. The shell prepends below
# read this and become no-ops otherwise.
PV_COMPAT_VDSO_ENABLED ?= "0"

python __anonymous () {
    bbmc = (d.getVar('BBMULTICONFIG') or '').split()
    if 'rpi-kernel' not in bbmc:
        return
    if d.getVar('TARGET_ARCH') != 'aarch64':
        return
    d.setVar('PV_COMPAT_VDSO_ENABLED', '1')
    triplet = d.getVar('COMPAT_TRIPLET')
    d.appendVar('EXTRA_OEMAKE', ' CROSS_COMPILE_COMPAT=%s-' % triplet)
    # mcdepends across multiconfig boundary; safe to add only when
    # rpi-kernel is actually enabled in BBMULTICONFIG.
    d.appendVarFlag('do_compile', 'mcdepends',
        ' mc::rpi-kernel:gcc-cross-arm:do_populate_sysroot'
        ' mc::rpi-kernel:binutils-cross-arm:do_populate_sysroot')
    d.appendVarFlag('do_compile_kernelmodules', 'mcdepends',
        ' mc::rpi-kernel:gcc-cross-arm:do_populate_sysroot'
        ' mc::rpi-kernel:binutils-cross-arm:do_populate_sysroot')
}

# Build a shim directory under the kernel's WORKDIR with un-prefixed
# symlinks (`as`, `ld`, `objcopy`, `objdump`, `gcc`, `cpp`, `nm`, `ar`,
# `ranlib`, `strip`) pointing at the v6 multiconfig's prefixed cross-
# binaries. Without this, gcc's internal assembler invocation finds
# the host /usr/bin/as ("as: unrecognized option '-EL'") because the
# Yocto cross-gcc package doesn't ship `as` in its libexec — it
# expects PATH to provide either the prefixed or un-prefixed name,
# and Kbuild's vdso32 rules end up calling plain `as` directly.
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
    if [ "${PV_COMPAT_VDSO_ENABLED}" = "1" ]; then
        setup_compat_toolchain_shim
    fi
}
do_compile_kernelmodules:prepend:aarch64 () {
    if [ "${PV_COMPAT_VDSO_ENABLED}" = "1" ]; then
        setup_compat_toolchain_shim
    fi
}
