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

SRC_URI[src.sha256sum] = "e190e14467e82513ecdbf3d586ce2062ceb4207f65eb70f1f6824a23845e2ba5"
SRC_URI[vendor.sha256sum] = "e929ca1b6df2dfdd4c424b12cd574b2e364ad7fe9c9cc4f30f3a24e96488815b"

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
