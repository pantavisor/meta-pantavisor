SUMMARY = "Pantavisor WiFi Connect - WiFi provisioning service"
SECTION = "pantacor"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvgo_mod

PVGO_PIE = "0"
CGO_ENABLED = "0"
GO_LINUXLOADER = ""

S = "${WORKDIR}"

SRC_URI = " \
    https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PV}/pvwificonnect.${PV}.src.tar.gz;name=src; \
    https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PV}/pvwificonnect.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[src.sha256sum] = "8accab4f8ded9b1e9bdb21ba477249615a0da133230c6aaf4fdcbfe4b0bb2570"
SRC_URI[vendor.sha256sum] = "8a93e633ddd4b10310881fe549eeef4b517128dd9ebd4e1d1fa9a32df2a71846"

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
