#
# This file was derived from the 'Hello World!' example recipe in the
# Yocto Project Development Manual.
#

DESCRIPTION = "libthttp library"
SECTION = "networking"
DEPENDS = "cmake mbedtls ca-certificates-native"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=bd0a4fad56a916f12a1c3cedb3976612"

FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}_${PV}:"

PACKAGES =+ "libthttp-certs"

SRC_URI = "git://github.com/pantavisor/libthttp;protocol=https;branch=master"
SRCREV = "ce916c562c5b11bcb0b5165043ded543dfea322a"
PE = "1"
PV = "011+git0"
PKGV = "${PV}+${GITPKGV}"

FILES:${PN}-certs += "/etc/thttp/certs"

S = "${WORKDIR}/git"

inherit cmake gitpkgv

CMAKE_BINARY_DIR = "${S}"

CMAKE_ARGS = "-DMBEDTLS_ROOT_DIR=${STAGING_DIR_TARGET}/usr"

# TLS trust store for pantavisor (PV_LIBTHTTP_CERTSDIR): the roots of the six
# largest public CAs, taken from the Mozilla bundle in ca-certificates.
# Names are files in /usr/share/ca-certificates/mozilla, without ".crt".
# Every file must parse with mbedtls, or pantavisor refuses the whole directory.
PV_TLS_CA_CERTS ?= "\
    ISRG_Root_X1 ISRG_Root_X2 \
    DigiCert_Global_Root_G2 DigiCert_Global_Root_G3 \
    DigiCert_TLS_RSA4096_Root_G5 DigiCert_TLS_ECC_P384_Root_G5 \
    USERTrust_RSA_Certification_Authority USERTrust_ECC_Certification_Authority \
    COMODO_RSA_Certification_Authority COMODO_ECC_Certification_Authority \
    Sectigo_Public_Server_Authentication_Root_R46 \
    Sectigo_Public_Server_Authentication_Root_E46 \
    GlobalSign_Root_CA_-_R3 GlobalSign_Root_CA_-_R6 \
    GlobalSign_ECC_Root_CA_-_R4 GlobalSign_ECC_Root_CA_-_R5 \
    GlobalSign_Root_R46 GlobalSign_Root_E46 \
    GTS_Root_R1 GTS_Root_R3 GTS_Root_R4 \
    Amazon_Root_CA_1 Amazon_Root_CA_2 Amazon_Root_CA_3 Amazon_Root_CA_4 \
"

do_install:append() {
    certsdir=${D}${sysconfdir}/thttp/certs
    mozilla=${STAGING_DATADIR_NATIVE}/ca-certificates/mozilla

    # replace the roots bundled in libthttp with the ones listed above
    rm -rf $certsdir
    install -d $certsdir
    found=0
    for name in ${PV_TLS_CA_CERTS}; do
        if [ -f $mozilla/$name.crt ]; then
            install -m 0644 $mozilla/$name.crt $certsdir/$name.crt
            found=$(expr $found + 1)
        else
            # Mozilla retires old roots; warn so a ca-certificates bump does not break the build
            bbwarn "PV_TLS_CA_CERTS: $name.crt is not in ca-certificates, skipping"
        fi
    done
    [ $found -gt 0 ] || bbfatal "PV_TLS_CA_CERTS: no root certificate installed"
}

#do_install() {
#  make install DESTDIR=${D}
#}

# Make sure our source directory (for the build) matches the directory structure in the tarball
#S = "${WORKDIR}/libthttp-${PV}"

