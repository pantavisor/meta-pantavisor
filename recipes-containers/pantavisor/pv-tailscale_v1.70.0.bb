SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "BSD"

inherit pvrexport

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/highercomve%2Fph-tailscale/packages/generic/tailscale/${PV}/tailscale.${PV}.${DOCKER_ARCH}.tgz;name=tailscale;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
