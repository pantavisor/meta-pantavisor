SUMMARY = "Pantahub Apps hosted packages"
LICENSE = "CLOSED"

inherit pvrexport

PANTAHUB_API = "api.pantahub.com"

PANTAHUB_USER ?= "pantavisor-apps"

BB_STRICT_CHECKSUM = "0"

SRC_URI += "\
	file://${BPN}.args.json \
	"

PVR_APP_ADD_EXTRA_ARGS += " \
	--volume /var/pvr-volume-boot:boot \
	--volume /var/pvr-volume-revision:revision \
	--volume /var/pvr-volume-permanent:permanent \
	"

#PVR_SRC_URI = "https://pvr.pantahub.com/asacasa/alpine-dbus_arm64v8/${PV}"
PVR_DOCKER_REF = "asac/alpine-dbus:latest"

