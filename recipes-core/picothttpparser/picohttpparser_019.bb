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

SRC_URI = "git://gitlab.com/pantacor/picohttpparser.git;protocol=https;branch=master"
SRCREV = "2136f9d16d9c8955fd0227b942db81dc5aed92a5"

S = "${WORKDIR}/git"

inherit cmake

CMAKE_BINARY_DIR = "${S}"
