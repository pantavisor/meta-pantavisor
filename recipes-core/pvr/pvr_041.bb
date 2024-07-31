DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantavisor"
HOMEPAGE = "https://golang.org/"

inherit go-mod native

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

SRC_URI = " \
	https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.src.tar.gz;name=pvr; \
	https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[pvr.sha256sum] = "406976aeabbc36f6c8ace86bef8d41ff9c7413358a1c4d919515a0255b922e67"
SRC_URI[vendor.sha256sum] = "b0b95318758cea6901be91e11bbb683af41faa77c1976cd91e9328695f169ce2"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

GOBUILDFLAGS += "-mod=vendor"

CGO_ENABLED = "0"

do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
  cp -fr ${S}/pvr-*/* ${S}/src/${GO_IMPORT}
}
do_unpack[postfuncs] += "relocate_source"

BBCLASSEXTEND = "native nativesdk"