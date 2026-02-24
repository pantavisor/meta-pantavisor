# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

SUMMARY = "Pantavisor Nginx Ingress Example"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvrexport

# Define the Docker image to use
PVR_DOCKER_REF = "nginx:alpine"

# Use custom args, services, and network files
SRC_URI += "file://${BPN}.args.json \
            file://${BPN}.services.json \
            file://${BPN}.network.json"
