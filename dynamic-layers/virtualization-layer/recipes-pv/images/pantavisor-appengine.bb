LICENSE = "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

include pantavisor-appengine.inc

DOCKER_IMAGE_NAME = "pantavisor-appengine"
DOCKER_IMAGE_TAG = "1.0"
DOCKER_IMAGE_EXTRA_TAGS = "latest"

