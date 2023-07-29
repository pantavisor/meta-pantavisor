SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI = "\
	https://${PANTAHUB_API}/exports/asacasa/pvr-sdk-example/${PV}/pvr-sdk-${PV}.tar.gz;subdir=pvrexport \
	file://mdev.json \
	"

