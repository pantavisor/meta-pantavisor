SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

# The prebuilt registry artifact, kept as an alternative to the from-source
# pv-pvr-sdk_2.0.0.bb. BitBake's vercmp sorts "v1.3.3" above "2.0.0", so
# without this it would win; select it with
# PREFERRED_VERSION_pv-pvr-sdk = "v1.3.3".
DEFAULT_PREFERENCE = "-1"


BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	https://gitlab.com/api/v4/projects/pantacor%2Fpv-platforms%2Fpvr-sdk/packages/generic/pvr-sdk/${PV}/pvr-sdk.${PV}.${DOCKER_ARCH}.tgz;name=pvr-sdk;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	"
