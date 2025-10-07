#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "libthttp library"
SECTION = "networking"
DEPENDS = "cmake mbedtls"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=bd0a4fad56a916f12a1c3cedb3976612"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}_${PV}:"

PACKAGES =+ "libthttp-certs"

SRC_URI = "git://gitlab.com/pantacor/libthttp.git;protocol=https;branch=master"
SRCREV = "9afaef8168d75c118896855e972a982a69cea12a"
PE = "1"
PKGV = "011+git0+${GITPKGV}"

FILES:${PN}-certs += "/etc/thttp/certs"

S = "${WORKDIR}/git"

inherit cmake gitpkgv

CMAKE_BINARY_DIR = "${S}"

CMAKE_ARGS = "-DMBEDTLS_ROOT_DIR=${STAGING_DIR_TARGET}/usr"

#do_install() {
#  make install DESTDIR=${D}
#}

# Make sure our source directory (for the build) matches the directory structure in the tarball
#S = "${WORKDIR}/libthttp-${PV}"

