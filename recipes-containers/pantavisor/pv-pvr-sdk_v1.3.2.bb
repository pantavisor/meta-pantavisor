SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport pantacor-component-docs

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
DOCS_FILES = "${WORKDIR}/pv-pvr-sdk/README.md"
DOCS_COMPONENT_NAME = "pvr-sdk"

SRC_URI += "file://pv-pvr-sdk/README.md"

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Fpvr-sdk/packages/generic/pvr-sdk/${PV}/pvr-sdk.${PV}.${DOCKER_ARCH}.tgz;name=pvr-sdk;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
