SUMMARY = "Target packages for the Pantavisor SDK sysroot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Not allarch: PANTAVISOR_FEATURES, which picks the LXC recipe and libkcapi
# below, can be set per machine.
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup

# Keep in step with DEPENDS in pantavisor_git.bb. libevent, libthttp and
# picohttpparser are built static-only; pvtx-static links the C library and
# zlib statically.
RDEPENDS:${PN} = " \
    ${TCLIBC}-staticdev \
    libevent-dev \
    libevent-staticdev \
    libthttp-dev \
    libthttp-staticdev \
    mbedtls-dev \
    picohttpparser-dev \
    picohttpparser-staticdev \
    zlib-dev \
    zlib-staticdev \
    ${PV_LXC_RECIPE}-dev \
    ${@bb.utils.contains('PANTAVISOR_FEATURES', 'dm-crypt', 'libkcapi-dev', '', d)} \
"

# For applications in containers. The -meta packages are explicit because
# pv-sdk.bb sets NO_RECOMMENDATIONS, which would drop the plugins; plugins-bad
# is there for kmssink, waylandsink, the V4L2 stateless decoders and the video
# parsers.
#
# ffmpeg, gstreamer1.0-libav and openh264 are left out: they need
# LICENSE_FLAGS_ACCEPTED "commercial", a decision for whoever distributes the
# SDK.
#
# libcamera comes from meta-multimedia, which only kas/sdk.yaml enables, along
# with the PACKAGECONFIGs these plugins rely on.
RDEPENDS:${PN} += " \
    gstreamer1.0-dev \
    gstreamer1.0-plugins-bad-dev \
    gstreamer1.0-plugins-bad-meta \
    gstreamer1.0-plugins-base-dev \
    gstreamer1.0-plugins-base-meta \
    gstreamer1.0-plugins-good-meta \
    libcamera-dev \
    libcamera-gst \
    libgpiod-dev \
    libgpiod-tools \
    libjpeg-turbo-dev \
    libv4l-dev \
    media-ctl \
    v4l-utils \
"
