SUMMARY = "Packages for the pvr SDK container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

# Mirrors the apk list in the SDK's Dockerfile final stage. Left out on purpose:
# the pantabox TUI and its tmux/dialog/ncurses, openrc (replaced by the
# pv-pvr-sdk-start entrypoint script), lxc (nothing in the SDK's scripts calls
# it), and logrotate/syslog (no syslog daemon in this distro, see
# pv-labutils_1.0.bb).
#
# pvcontrol (and, through it, json-sh) is pulled in by container-pvrexport.
RDEPENDS:${PN} = "\
    ca-certificates \
    coreutils \
    curl \
    dropbear \
    jq \
    nano \
    openssh-scp \
    pantavisor-pvtx-static \
    pvtx-app \
    pv-busybox-httpd \
    pvr \
    shadow \
    socat \
    squashfs-tools \
    sudo \
    tar \
    wget \
"
