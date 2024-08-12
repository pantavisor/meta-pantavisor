SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

PVCONT_NAME="os"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Fdebian-nm/packages/generic/debian-nm/${PV}/debian-nm.${PV}.${DOCKER_ARCH}.tgz;name=os;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	file://mdev.json \
	"
	