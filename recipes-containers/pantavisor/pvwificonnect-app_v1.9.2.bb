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

SRC_URI[src.sha256sum] = "93068ff78978dd9e36a32ea648af14910e53d3abdfe20347f65b10953e3984b2"
SRC_URI[vendor.sha256sum] = "73265365ee1e6a1ad3617ecefe8759dadae76e1dd017c838d222912197ee8610"

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
