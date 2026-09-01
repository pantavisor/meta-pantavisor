SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

# PVSM_ARCH selects which prebuilt container arch to fetch, defaulting to the
# machine's DOCKER_ARCH. It can be overridden per image: the Raspberry Pi CM5
# (BCM2712) only has an arm64 kernel (16K pages), so a 32-bit arm32v6 container
# faults at exec. The benchmark overlay sets PVSM_ARCH = "arm64v8" for the CM5;
# 32-bit-kernel devices keep arm32v6.
PVSM_ARCH ?= "${DOCKER_ARCH}"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/highercomve%2Fpvsm/packages/generic/pvsm-pvexport/${PV}/pvsm.${PV}.${PVSM_ARCH}.tgz;name=pvsm;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
