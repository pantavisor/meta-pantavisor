SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Fpvr-sdk/packages/generic/pvr-sdk/${PV}/pvr-sdk.${PV}.${DOCKER_ARCH}.tgz;name=pvr-sdk;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
