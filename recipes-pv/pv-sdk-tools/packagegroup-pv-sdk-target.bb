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
