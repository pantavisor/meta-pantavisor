DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantavisor"
HOMEPAGE = "https://golang.org/"

inherit go-mod deploy native

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

SRC_URI = " \
	https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.src.tar.gz;name=pvr; \
	https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[pvr.sha256sum] = "2079ac9b17f3e84553f08e741bea80fcd19c863fb06c96bb9a1c9955bd8234ab"
SRC_URI[vendor.sha256sum] = "c278a5059fe91946c2da0a6ff7cc3f9c8959a5e0eaacc48ff023d95bbba19748"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

GOBUILDFLAGS += "-mod=vendor"
GO_LINKMODE:class-nativesdk = ""
GO_LINKMODE:class-native = ""

CGO_ENABLED = "0"

do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
  cp -fr ${S}/pvr-*/* ${S}/src/${GO_IMPORT}
}
do_patch[postfuncs] += "relocate_source"

do_deploy[sstate-outputdirs] = "${DEPLOY_DIR_TOOLS}"
do_deploy[dirs] += "${DEPLOY_DIR_TOOLS}"

do_deploy() {
	install -m 755 ${B}/bin/pvr ${DEPLOY_DIR_TOOLS}/pvr-${PACKAGE_ARCH}
}

addtask deploy after do_install

BBCLASSEXTEND = "native nativesdk"
