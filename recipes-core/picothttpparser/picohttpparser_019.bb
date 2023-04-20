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

SRC_URI = "file://picohttpparser-src"

S = "${WORKDIR}/picohttpparser-src"

inherit cmake

CMAKE_BINARY_DIR = "${S}"
