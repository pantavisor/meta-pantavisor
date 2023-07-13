#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "picohttpparser library"
SECTION = "networking"
DEPENDS = "cmake"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "git://gitlab.com/pantacor/picohttpparser;protocol=https;branch=cmake"
SRCREV = "8dc2781fe98e3a3879092a39ec20d5fb2278a2ac"

S = "${WORKDIR}/git"

inherit cmake

CMAKE_BINARY_DIR = "${S}"
