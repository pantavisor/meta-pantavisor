SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

PANTAHUB_API = "api.pantahub.com"

PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI = "\
	https://${PANTAHUB_API}/exports/asacasa/connman-example/${PV}/connman-example-${PV}.tar.gz;subdir=${BPN}-${PV}/pvrrepo/.pvr \
	file://mdev.json \
	"

