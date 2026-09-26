SUMMARY = "pv-mqtt-sdk - Pantahub MQTT agent for Pantavisor"
DESCRIPTION = "Registers the device, holds the Pantahub MQTT message plane, \
installs pushed revisions through pv-ctrl and syncs device-meta/user-meta, \
for devices whose pantavisor remote control is disabled."
SECTION = "pantacor"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit pvgo_mod

S = "${WORKDIR}"

# Tarballs are attached to the GitHub release of tag ${PV} by CI
# (.github/workflows/ci.yml, scripts/source-package.sh).
PV_MQTT_SDK_RELEASES = "https://github.com/pantavisor/pv-mqtt-sdk/releases/download/${PV}"

SRC_URI = " \
    ${PV_MQTT_SDK_RELEASES}/pv-mqtt-sdk.${PV}.src.tar.gz;name=src \
    ${PV_MQTT_SDK_RELEASES}/pv-mqtt-sdk.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

# From pv-mqtt-sdk.${PV}.sha256 in the release assets.
SRC_URI[src.sha256sum] = "014ca0b88b008fb0409ebc004f78fd65cb4ce6063232c489a621aaa3d6d65f5b"
SRC_URI[vendor.sha256sum] = "50adab3c0ec46670ee9dbe819ce39ab5d3a40a5d2e2a8a4a51b29d135d610b5a"

GO_IMPORT = "github.com/pantavisor/pv-mqtt-sdk"
export GO111MODULE = "on"

GOBUILDFLAGS += "-mod=vendor"
GO_LINKSHARED = ""
GO_EXTRA_LDFLAGS:append = " -X ${GO_IMPORT}/pkg/config.Version=${PV}"

GO_INSTALL = "${GO_IMPORT}"

do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
    cp -fr ${S}/pv-mqtt-sdk/* ${S}/src/${GO_IMPORT}
}
do_patch[postfuncs] += "relocate_source"

# The agent verifies the Hub's TLS certificate with the system bundle.
RDEPENDS:${PN} += "ca-certificates"

FILES:${PN} = "${bindir}/pv-mqtt-sdk"
