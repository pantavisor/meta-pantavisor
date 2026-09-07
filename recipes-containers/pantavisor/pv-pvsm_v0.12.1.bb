SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

# Prebuilt container arch; override per image (e.g. arm64v8 on the CM5).
PVSM_ARCH ?= "${DOCKER_ARCH}"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/highercomve%2Fpvsm/packages/generic/pvsm-pvexport/${PV}/pvsm.${PV}.${PVSM_ARCH}.tgz;name=pvsm;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
