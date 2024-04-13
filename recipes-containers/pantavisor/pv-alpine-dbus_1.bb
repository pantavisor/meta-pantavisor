SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

PANTAHUB_API = "api.pantahub.com"

PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	file://mdev.json \
	"

PVR_SRC_URI = "https://pvr.pantahub.com/asacasa/alpine-dbus_arm64v8/${PV}"

