SUMMARY = "Rockchip USB download tool (rockusb / Maskrom)"
DESCRIPTION = "Host-side tool that speaks the rockusb protocol over USB to load a \
loader into SoC SRAM and program the on-board flash of a Rockchip device held in \
Maskrom or Loader mode. Used by pv-flash-bundle for Rockchip factory flashing."
HOMEPAGE = "https://github.com/rockchip-linux/rkdeveloptool"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://license.txt;md5=ea9445d9cc03d508cf6bb769d15a54ef"

SRC_URI = "git://github.com/rockchip-linux/rkdeveloptool.git;branch=master;protocol=https"
SRCREV = "304f073752fd25c854e1bcf05d8e7f925b1f4e14"
PV = "1.32+git"

S = "${WORKDIR}/git"

DEPENDS = "libusb1"

inherit autotools pkgconfig

# Upstream Makefile.am builds with -Werror; cross toolchains surface benign
# -Wstringop-overflow / -Wdeprecated-declarations that would otherwise fail.
CXXFLAGS:append = " -Wno-error"

# Only the host-side flasher is needed; pv-flash-bundle pulls the native variant.
BBCLASSEXTEND = "native nativesdk"
