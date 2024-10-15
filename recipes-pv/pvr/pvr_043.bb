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

SRC_URI[pvr.sha256sum] = "db044cfe220ee646c30b8dce51b2189f8a6a1e4393945238f21e918cbb4b3f46"
SRC_URI[vendor.sha256sum] = "31714ada0098727131b18bee122253521c9fb3cf2f097f60d3ddb53abdd3ec2f"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

GOBUILDFLAGS += "-mod=vendor"

CGO_ENABLED = "0"

do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
  cp -fr ${S}/pvr-*/* ${S}/src/${GO_IMPORT}
}
do_patch[postfuncs] += "relocate_source"

BBCLASSEXTEND = "native nativesdk"
