SUMMARY = "Pantavisor Ingress Test Container"
DESCRIPTION = "A single ingress point demonstrating TCP and HTTP routing to multiple backends."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-ingress"

# Ingress doesn't need much, just a placeholder to hold the network namespace
IMAGE_INSTALL += "busybox"

PVRIMAGE_AUTO_MDEV = "0"

SRC_URI += "file://${PN}.args.json \
            file://${PN}.config.json"

PVR_APP_ADD_EXTRA_ARGS += ""
