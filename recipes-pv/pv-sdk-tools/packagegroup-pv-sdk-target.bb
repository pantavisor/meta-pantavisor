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

# Runtime, formats and system libraries
RDEPENDS:${PN} += " \
    acl-dev \
    attr-dev \
    bzip2-dev \
    cjson-dev \
    dbus-dev \
    eudev-dev \
    expat-dev \
    flatbuffers-dev \
    glib-2.0-dev \
    jansson-dev \
    json-c-dev \
    keyutils-dev \
    libatomic-dev \
    libcap-dev \
    libffi-dev \
    libpcre2-dev \
    libseccomp-dev \
    libsqlite3-dev \
    libstdc++-dev \
    libxml2-dev \
    libyaml-dev \
    linux-libc-headers-dev \
    lz4-dev \
    ncurses-dev \
    protobuf-c-dev \
    protobuf-dev \
    readline-dev \
    util-linux-dev \
    xz-dev \
    zeromq-dev \
    zstd-dev \
"

# Security
RDEPENDS:${PN} += " \
    ca-certificates \
    libp11-dev \
    libsodium-dev \
    openssl-dev \
    optee-client-dev \
    p11-kit-dev \
    tpm2-openssl \
    libtss2-dev \
"

# Networking
RDEPENDS:${PN} += " \
    bluez5-dev \
    curl-dev \
    libmbim-dev \
    libmnl-dev \
    libnl-dev \
    libpcap-dev \
    libqmi-dev \
    libwebsockets-dev \
    linuxptp \
    modemmanager-dev \
    mosquitto-dev \
    nghttp2-dev \
    paho-mqtt-c-dev \
    wpa-supplicant \
"

# Hardware I/O
RDEPENDS:${PN} += " \
    can-utils \
    i2c-tools \
    i2c-tools-dev \
    libevdev-dev \
    libftdi-dev \
    libgpiod-dev \
    libgpiod-tools \
    libiio-dev \
    libserialport-dev \
    libsocketcan-dev \
    libusb1-dev \
"

# Industrial and motor control. rt-tests is left out: its recipe does not
# support musl.
RDEPENDS:${PN} += " \
    libeigen-dev \
    libmodbus-dev \
    liburcu-dev \
    open62541-dev \
"

# Multimedia. The -meta packages are explicit because pv-sdk.bb sets
# NO_RECOMMENDATIONS, which would drop the plugins; plugins-bad is there for
# kmssink, waylandsink, the V4L2 stateless decoders, WebRTC and the video
# parsers. libcamera comes from meta-multimedia, which only kas/sdk.yaml enables,
# along with the PACKAGECONFIGs these plugins rely on.
RDEPENDS:${PN} += " \
    alsa-lib-dev \
    gstreamer1.0-dev \
    gstreamer1.0-plugins-bad-dev \
    gstreamer1.0-plugins-bad-meta \
    gstreamer1.0-plugins-base-dev \
    gstreamer1.0-plugins-base-meta \
    gstreamer1.0-plugins-good-meta \
    gstreamer1.0-rtsp-server-dev \
    libavif-dev \
    libcamera-dev \
    libcamera-gst \
    libjpeg-turbo-dev \
    libpng-dev \
    libv4l-dev \
    libwebp-dev \
    media-ctl \
    opencv-dev \
    v4l-utils \
"

# Graphics
RDEPENDS:${PN} += " \
    cairo-dev \
    fontconfig-dev \
    freetype-dev \
    fribidi-dev \
    harfbuzz-dev \
    icu-dev \
    libdrm-dev \
    libegl-mesa-dev \
    libepoxy-dev \
    libgbm-dev \
    libgles2-mesa-dev \
    libinput-dev \
    librsvg-dev \
    libxkbcommon-dev \
    mesa-dev \
    mtdev-dev \
    pixman-dev \
    seatd-dev \
    ttf-dejavu-sans \
    vulkan-headers-dev \
    vulkan-loader-dev \
    wayland-dev \
    wayland-protocols \
    weston \
    xkeyboard-config \
"

# UI toolkits. WPE WebKit and cog are left out for now: wpewebkit alone
# compiles for more than 2 hours, which pushed the SDK build past the CI
# job's 6-hour limit.
RDEPENDS:${PN} += " \
    gdk-pixbuf-dev \
    gobject-introspection-dev \
    graphene-dev \
    gtk4-dev \
    libadwaita-dev \
    libsdl2-dev \
    libsoup-dev \
    pango-dev \
    qtbase-dev \
    qtcharts-dev \
    qtdeclarative-dev \
    qtgraphs-dev \
    qtimageformats \
    qtlocation-dev \
    qtlottie-dev \
    qtmqtt-dev \
    qtmultimedia-dev \
    qtpositioning-dev \
    qtquick3d-dev \
    qtserialbus-dev \
    qtserialport-dev \
    qtshadertools-dev \
    qtsvg-dev \
    qtvirtualkeyboard-dev \
    qtwayland-dev \
"

# Python
RDEPENDS:${PN} += " \
    gstreamer1.0-python \
    python3-can \
    python3-cffi \
    python3-cryptography \
    python3-dbus \
    python3-dev \
    python3-gpiod \
    python3-modules \
    python3-numpy \
    python3-opencv \
    python3-paho-mqtt \
    python3-protobuf \
    python3-pygobject \
    python3-pymodbus \
    python3-pyserial \
    python3-pyyaml \
    python3-requests \
    python3-smbus2 \
    python3-spidev \
"

# Debugging
RDEPENDS:${PN} += " \
    breakpad-dev \
    elfutils-dev \
    libunwind-dev \
    lttng-ust-dev \
"

# Software H.264/H.265 and the other codecs that need LICENSE_FLAGS_ACCEPTED
# "commercial", a decision for whoever distributes the SDK.
RDEPENDS:${PN} += "${@bb.utils.contains('LICENSE_FLAGS_ACCEPTED', 'commercial', ' \
    ffmpeg-dev \
    gstreamer1.0-libav \
    gstreamer1.0-plugins-ugly-meta \
    x264-dev \
    x265-dev \
', '', d)}"
