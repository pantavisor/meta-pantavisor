#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "picohttpparser library"
SECTION = "networking"
DEPENDS = "cmake"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}_${PV}:"

SRC_URI = "git://gitlab.com/pantacor/picohttpparser.git;protocol=https;branch=cmake"
SRCREV = "90c5171df540bcd02fa8a3f773a25ae13eaca7ac"

S = "${WORKDIR}/git"

inherit cmake

CMAKE_BINARY_DIR = "${S}"
