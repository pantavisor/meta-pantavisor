SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/highercomve%2Fpvsm/packages/generic/pvsm-pvexport/${PV}/pvsm.${PV}.${DOCKER_ARCH}.tgz;name=pvsm;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
