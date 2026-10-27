SUMMARY = "pv-mqtt-sdk - Pantahub MQTT agent for Pantavisor"
DESCRIPTION = "Registers the device, holds the Pantahub MQTT message plane, \
installs pushed revisions through pv-ctrl and syncs device-meta/user-meta, \
for devices whose pantavisor remote control is disabled."
SECTION = "pantacor"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit pvgo_mod

S = "${WORKDIR}"

# The repository is private: the fetch authenticates with a GitHub token in
# ~/.netrc (CI writes one from a secret). vendor/ is committed, so the build
# needs no module download.
SRC_URI = "git://github.com/pantavisor/pv-mqtt-sdk.git;protocol=https;branch=main;destsuffix=src/${GO_IMPORT}"
# v0.1.13; pinned instead of tag=${PV}, which Kirkstone cannot resolve.
SRCREV = "28edec0c1ddd94f59dbe2a2d52b4c896f4108472"

GO_IMPORT = "github.com/pantavisor/pv-mqtt-sdk"
export GO111MODULE = "on"

GOBUILDFLAGS += "-mod=vendor"
GO_LINKSHARED = ""
GO_EXTRA_LDFLAGS:append = " -X ${GO_IMPORT}/pkg/config.Version=${PV}"

GO_INSTALL = "${GO_IMPORT}"

# The agent verifies the Hub's TLS certificate with the system bundle.
RDEPENDS:${PN} += "ca-certificates"

FILES:${PN} = "${bindir}/pv-mqtt-sdk"
