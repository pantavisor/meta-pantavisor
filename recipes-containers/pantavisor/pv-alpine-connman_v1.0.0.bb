SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "MIT"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

PVCONT_NAME="os"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Falpine-connman/packages/generic/alpine-connman/${PV}/alpine-connman.${PV}.${DOCKER_ARCH}.tgz;name=os;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	file://mdev.json \
	"

