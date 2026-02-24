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

SRC_URI = "git://github.com/pantavisor/picohttpparser;protocol=https;branch=pv/master"
SRCREV = "fbefe74fa3d7802de2396349ba7daa15a9e93745"

S = "${WORKDIR}/git"

inherit cmake

CMAKE_BINARY_DIR = "${S}"
