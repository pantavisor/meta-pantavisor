SUMMARY = "DevicePass.ai device-side management container"
DESCRIPTION = "pv-devicepass container providing HTTP management API, reverse proxy \
to container REST services, skill manifest collection, and identity headers."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-devicepass-container"
PVRIMAGE_AUTO_MDEV = "0"

IMAGE_INSTALL += "pantavisor-pv-devicepass busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://${PN}.services.json \
            file://${PN}.args.json \
            file://${PN}.lxc-extra.conf \
            "

# OCI/LXC entrypoint — pass tunnel socket if xconnect injects it
PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-devicepass --config=Cmd=--tunnel-socket=/run/pv/services/tunnel.sock"

# pv-devicepass is a management container — needs host /proc access for
# direct socket proxying to container namespaces via /proc/PID/root/
PVR_APP_ADD_GROUP = "root"
