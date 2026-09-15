SUMMARY = "Android platform tools (adb, fastboot) for the host side"
DESCRIPTION = "CMake packaging of the AOSP platform-tools by the Alpine \
android-tools maintainer, built so the host-side adb and fastboot run on the \
target. meta-oe's android-tools is the wrong shape for a lab controller: the \
scarthgap recipe is 2015 AOSP with glibc patches, and master ships only adbd \
to the target and keeps adb/fastboot for class-native."
HOMEPAGE = "https://github.com/nmeum/android-tools"

# Apache-2.0: adb, core, libbase, boringssl. MIT: fmtlib. e2fsprogs is
# GPL-2.0 for the tools and LGPL-2.0 for lib/ext2fs; f2fs-tools is GPL-2.0.
LICENSE = "Apache-2.0 & MIT & GPL-2.0-only & LGPL-2.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57 \
                    file://vendor/fmtlib/LICENSE;md5=b9257785fc4f3803a4b71b76c1412729 \
                    file://vendor/boringssl/LICENSE;md5=0131a611be3a37729f61e0b26319da57 \
                    file://vendor/e2fsprogs/NOTICE;md5=d50be0580c0b0a7fbc7a4830bbe6c12b \
                    file://vendor/f2fs-tools/COPYING;md5=362b4b2594cd362b874a97718faa51d3 \
"

# The release tarball is what Alpine builds: the AOSP submodules are already
# vendored and patched (CPack strips patches/), so no git or Go at build time.
SRC_URI = "https://github.com/nmeum/android-tools/releases/download/${PV}/android-tools-${PV}.tar.xz \
           file://0001-vendor-look-up-protobuf-in-module-mode-only.patch \
"
SRC_URI[sha256sum] = "2725d09f892a3a38e534429f47a321f58ecf6a3169caa42c915fb2cb7d46be0e"

# googletest is not for tests: libziparchive's public zip_writer.h includes
# <gtest/gtest_prod.h> for FRIEND_TEST unconditionally. Header-only.
DEPENDS = "abseil-cpp brotli googletest lz4 pcre2 protobuf protobuf-native zstd"

inherit cmake pkgconfig bash-completion

# Bundled fmt is what upstream builds and tests against (12.0); meta-oe
# scarthgap ships 10.2.1.
#
# Bundled libusb (1.0.29, static, netlink hotplug) because adb's
# usb_libusb_device.cpp uses the SuperSpeedPlus x2 API - LIBUSB_SPEED_SUPER_PLUS_X2
# and libusb_get_ssplus_usb_device_capability_descriptor - which arrived in
# libusb 1.0.28; poky scarthgap has 1.0.27. udev stays off: a container has no
# udev, and every other libusb user in pv-labutils keeps the system libusb1.
EXTRA_OECMAKE = " \
    -DANDROID_TOOLS_USE_BUNDLED_FMT=ON \
    -DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON \
    -DProtobuf_PROTOC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/protoc \
"

# protobuf 4.x's generated .pb.cc code calls abseil directly (CHECK macros ->
# absl::log_internal), but module-mode FindProtobuf hands the build a bare
# libprotobuf.so with none of the transitive absl link deps that config mode
# would carry. Let ld follow libprotobuf.so's own DT_NEEDED entries to resolve
# them - the same line Alpine's APKBUILD uses for the same reason.
LDFLAGS:append = " -Wl,--copy-dt-needed-entries"

# Vendored BoringSSL is built as static libraries and linked in.
COMPATIBLE_HOST:powerpc = "(null)"
COMPATIBLE_HOST:powerpc64 = "(null)"
COMPATIBLE_HOST:powerpc64le = "(null)"

PACKAGES =+ "${PN}-python"

# The mkbootimg family and avbtool/mkdtboimg are Python scripts; keep them off
# the compiled tools so a container that only needs adb/fastboot does not pull
# in python3.
FILES:${PN}-python = " \
    ${bindir}/avbtool \
    ${bindir}/mkbootimg \
    ${bindir}/mkdtboimg \
    ${bindir}/repack_bootimg \
    ${bindir}/unpack_bootimg \
    ${datadir}/android-tools/mkbootimg \
"
RDEPENDS:${PN}-python = "python3-core"

FILES:${PN} += " \
    ${datadir}/android-tools/completions \
    ${datadir}/zsh/site-functions \
"

# meta-oe scarthgap carries android-tools_5.1.1.r37 at the same BBFILE_PRIORITY;
# bitbake resolves the same-priority case by highest PV, so this one wins
# deterministically wherever this layer is present.
