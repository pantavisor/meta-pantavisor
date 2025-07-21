SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpvwificonnect/packages/generic/pvwificonnect/${PV}/pvwificonnect.${PV}.${DOCKER_ARCH}.tgz;name=pvwificonnect;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"


