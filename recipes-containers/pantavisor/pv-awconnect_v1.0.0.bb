SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

PVCONT_NAME="awconnect"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Fwifi-connect/packages/generic/awconnect/${PV}/awconnect.${PV}.${DOCKER_ARCH}.tgz;name=awconnect;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	file://mdev.json \
	"
