SUMMARY = "Tooling for the Pantacor lab controller container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

# Mirrors the apk list in labutils' Dockerfile final stage, split so a lab
# controller that only power-cycles boards need not carry the flashing half.
PACKAGES = "\
    ${PN} \
    ${PN}-flash \
    ${PN}-power \
    ${PN}-serial \
    ${PN}-shell \
"

RDEPENDS:${PN} = "\
    ${PN}-flash \
    ${PN}-power \
    ${PN}-serial \
    ${PN}-shell \
"

SUMMARY:${PN}-flash = "Board flashing and USB storage muxing"
# rkdeveloptool already exists in this layer for pv-flash-bundle, which only ever
# pulled the native variant - this is the first consumer of the target build.
RDEPENDS:${PN}-flash = "\
    android-tools \
    dfu-util \
    rkdeveloptool \
    usbsdmux \
    usbutils \
    uuu \
"

SUMMARY:${PN}-power = "Per-port USB and mains power switching"
RDEPENDS:${PN}-power = "\
    uhubctl \
    sispmctl \
"

SUMMARY:${PN}-serial = "Serial consoles"
RDEPENDS:${PN}-serial = "\
    picocom \
    screen \
"

SUMMARY:${PN}-shell = "Shell, scripting and Pantavisor tooling"
# pvcontrol (and, through it, json-sh) is pulled in by container-pvrexport, so
# it is deliberately absent here.
RDEPENDS:${PN}-shell = "\
    bash \
    coreutils \
    curl \
    expect \
    git \
    iproute2 \
    jq \
    openssh-scp \
    openssh-sftp \
    openssh-ssh \
    pvr \
    python3 \
    python3-pip \
    python3-requests \
    rsync \
    socat \
    sudo \
    vim \
    xz \
"

# labutils' final stage also carries build-base/cmake/openssl-dev so a CI job can
# compile in place. That is left out entirely rather than packaged as an unused
# subpackage: a packagegroup's RDEPENDS are built whether or not the package is
# installed, so listing them here would pull target gcc and cmake into every
# pv-labutils build. A lab that needs them adds
#   IMAGE_INSTALL:append = " packagegroup-core-buildessential cmake openssl-dev"
# to the image recipe.
