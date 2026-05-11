
# meta-pantavisor/dynamic-layers/meta-raspberrypi/recipes-kernel/linux/linux-raspberrypi_%.bbappend
#
# Enable CONFIG_COMPAT_VDSO=y for arm64 kernels by pointing
# CROSS_COMPILE_COMPAT at a WORKDIR-private shim of the 32-bit ARM
# cross-toolchain (gcc + binutils) sourced from the rpi-kernel
# multiconfig. PATH is intentionally NOT modified — see the comment
# on setup_compat_toolchain_shim for why.
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
# the shim materialization) is gated on rpi-kernel actually being
# part of BBMULTICONFIG. On a non-multiconfig arm64 build this
# bbappend is a no-op.

# The cross-toolchain triplet's libc suffix depends on the distro's
# C library (musl vs glibc). Pantavisor builds against musl, so the
# arm32 cross-toolchain is `arm-poky-linux-musleabi-`. On a glibc
# distro it would be `arm-poky-linux-gnueabi-`.
COMPAT_LIBC_SUFFIX = "${@'musleabi' if d.getVar('TCLIBC') == 'musl' else 'gnueabi'}"
COMPAT_TRIPLET = "arm${TARGET_VENDOR}-linux-${COMPAT_LIBC_SUFFIX}"

# The 32-bit ARM cross-gcc and cross-binutils are produced by the
# rpi-kernel multiconfig (MACHINE=raspberrypi). Each multiconfig has
# an isolated `recipe-sysroot-native`, so the arm64 kernel build
# can't see the v6 multiconfig's binaries by default. We reference
# both component bin dirs directly via absolute paths inside the
# shim (no PATH manipulation).
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
    # CROSS_COMPILE_COMPAT points at the WORKDIR shim dir, not at the
    # multiconfig sysroots. The shim contains only PREFIXED names:
    # a wrapper for gcc/g++/cpp that adds `-B<binutils-dir>/`, and
    # plain symlinks for the binutils tools. This means no directory
    # is ever prepended to PATH, so HOSTCC (scripts/dtc et al.) keeps
    # the clean host PATH and never picks up the arm cross binutils.
    shim = d.getVar('COMPAT_SHIM_DIR')
    triplet = d.getVar('COMPAT_TRIPLET')
    d.appendVar('EXTRA_OEMAKE',
        ' CROSS_COMPILE_COMPAT=%s/%s-' % (shim, triplet))
    # mcdepends across multiconfig boundary; safe to add only when
    # rpi-kernel is actually enabled in BBMULTICONFIG.
    d.appendVarFlag('do_compile', 'mcdepends',
        ' mc::rpi-kernel:gcc-cross-arm:do_populate_sysroot'
        ' mc::rpi-kernel:binutils-cross-arm:do_populate_sysroot')
    d.appendVarFlag('do_compile_kernelmodules', 'mcdepends',
        ' mc::rpi-kernel:gcc-cross-arm:do_populate_sysroot'
        ' mc::rpi-kernel:binutils-cross-arm:do_populate_sysroot')
}

# Build a per-build shim dir under WORKDIR containing only PREFIXED
# names (matching CROSS_COMPILE_COMPAT). PATH is NOT modified, so the
# rest of the do_compile task — in particular HOSTCC for kernel host
# tools like scripts/dtc — sees the unchanged host PATH and resolves
# host gcc + /usr/bin/as as normal.
#
# Two pieces:
#
#  1. A wrapper script `<triplet>-gcc` (also linked as `<triplet>-g++`
#     and `<triplet>-cpp`) that exec's the real cross-gcc with an
#     extra `-B${COMPAT_BUTILS_BIN_DIR}/` flag. gcc's `-B<prefix>/`
#     lookup tries `<prefix><target>as` (= `<dir>/arm-poky-linux-
#     musleabi-as`) first, which exists in the v6 multiconfig's
#     binutils-cross-arm sysroot — so gcc's internal assembler
#     invocation resolves without any PATH hint.
#
#  2. Plain symlinks for the binutils tools the kernel calls directly
#     via `${CROSS_COMPILE_COMPAT}<tool>` (ld for the vdso32 link,
#     objcopy/objdump/nm/etc. for post-processing). These are kept
#     PREFIXED on disk so they can never be hit by an un-prefixed
#     PATH lookup from a host-side compiler.
setup_compat_toolchain_shim () {
    install -d ${COMPAT_SHIM_DIR}
    # The wrapper holds absolute paths baked in at bitbake parse time;
    # only `$@` is left for the shell to expand at runtime. The `-B`
    # flag points at the shim dir itself, which also contains the
    # un-prefixed binutils symlinks below — gcc's `-B<prefix>/`
    # lookup uses `<prefix><progname>` (un-prefixed), it does NOT
    # auto-add the cross target triplet.
    cat > "${COMPAT_SHIM_DIR}/${COMPAT_TRIPLET}-gcc" <<EOF
#!/bin/sh
exec "${COMPAT_GCC_BIN_DIR}/${COMPAT_TRIPLET}-gcc" -B"${COMPAT_SHIM_DIR}/" "\$@"
EOF
    chmod +x "${COMPAT_SHIM_DIR}/${COMPAT_TRIPLET}-gcc"
    # g++ and cpp use the same driver; same -B handling applies.
    ln -sf "${COMPAT_TRIPLET}-gcc" "${COMPAT_SHIM_DIR}/${COMPAT_TRIPLET}-g++"
    ln -sf "${COMPAT_TRIPLET}-gcc" "${COMPAT_SHIM_DIR}/${COMPAT_TRIPLET}-cpp"
    # Binutils tools — each linked twice:
    #   <triplet>-<tool>   so Kbuild's direct ${CROSS_COMPILE_COMPAT}<tool>
    #                      calls (ld for vdso32 link, objcopy/objdump/nm/…)
    #                      resolve inside the shim.
    #   <tool>             so cross-gcc's internal `as`/`ld` lookup via
    #                      the `-B<shim>/` prefix finds it (gcc tries
    #                      "<prefix><progname>" un-prefixed, NOT
    #                      "<prefix><triplet>-<progname>").
    # Critically the shim dir is NEVER added to PATH, so the un-prefixed
    # symlinks here cannot poison HOSTCC.
    for tool in as ld objcopy objdump nm ar ranlib strip; do
        ln -sf "${COMPAT_BUTILS_BIN_DIR}/${COMPAT_TRIPLET}-$tool" \
            "${COMPAT_SHIM_DIR}/${COMPAT_TRIPLET}-$tool"
        ln -sf "${COMPAT_TRIPLET}-$tool" "${COMPAT_SHIM_DIR}/$tool"
    done
}

# Both `do_compile` (vmlinux) AND `do_compile_kernelmodules` (in-tree
# modules) run vdso_prepare, so both need the shim materialized in
# WORKDIR. Without the second one, `do_compile_kernelmodules` re-fails
# on `arm-poky-linux-musleabi-gcc: not found` if WORKDIR was wiped
# between tasks.
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
