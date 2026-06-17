SUMMARY = "Pantavisor WiFi Connect - WiFi provisioning service"
SECTION = "pantacor"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvgo_mod

S = "${WORKDIR}"

SRC_URI = " \
    https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PV}/pvwificonnect.${PV}.src.tar.gz;name=src; \
    https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PV}/pvwificonnect.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[src.sha256sum] = "928affcda9dbfb5d38db6e1950d10340085152d45fb61f0af68adb59bb74760a"
SRC_URI[vendor.sha256sum] = "043ead8cf3d83297c4128604d5a6bae3c0a2f44bf1af9ecf13e9a4732cdc99f8"

GO_IMPORT = "gitlab.com/pantacor/pvwificonnect"
export GO111MODULE = "on"

GOBUILDFLAGS += "-mod=vendor"
GO_LINKSHARED = ""

GO_INSTALL = " \
    ${GO_IMPORT} \
    ${GO_IMPORT}/cmd/pvwificonnect-cli \
"

do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
    cp -fr ${S}/pvwificonnect/* ${S}/src/${GO_IMPORT}
}
do_patch[postfuncs] += "relocate_source"

do_install:append() {
    # Install static assets and templates
    install -d ${D}/app/static
    install -d ${D}/app/templates
    cp -r ${S}/src/${GO_IMPORT}/static/* ${D}/app/static/
    cp -r ${S}/src/${GO_IMPORT}/templates/* ${D}/app/templates/

    # Move pvwificonnect binary to /app/
    install -d ${D}/app
    if [ -f ${D}${bindir}/pvwificonnect ]; then
        mv ${D}${bindir}/pvwificonnect ${D}/app/pvwificonnect
    fi

    # pvwificonnect-cli stays in /usr/bin/
}

FILES:${PN} = "/app ${bindir}/pvwificonnect-cli"
