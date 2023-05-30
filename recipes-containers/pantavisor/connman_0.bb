SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

PANTAHUB_API = "api2.pantahub.com"

PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI = "\
	https://${PANTAHUB_API}/exports/asacasa/connman-example/0/connman-example-0.tar.gz;subdir=pvrexport \
	file://mdev.json \
	"

