SUMMARY = "Pantavisor pvr SDK management container"
DESCRIPTION = "On-device counterpart of the pvr CLI: pvtx REST API and web UI, \
ssh access and Pantahub auto-follow. The pantabox TUI is not part of this build. Builds gitlab.com/pantacor/pv-platforms/pvr-sdk \
from source instead of fetching the prebuilt registry artifact."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${WORKDIR}/sdk-src/LICENSE;md5=70175346ce0d7913626f30a67d153851"

inherit image container-pvrexport extrausers

IMAGE_BASENAME = "pv-pvr-sdk"

# Board machine confs append their own rootfs types to every image; this one
# must only ever produce a pvrexport.
IMAGE_FSTYPES = "pvrexportit"

# No init system: /usr/bin/pv-pvr-sdk-start is the container's entrypoint.
IMAGE_INSTALL = "base-files base-passwd busybox packagegroup-pv-pvr-sdk"
IMAGE_LINGUAS = ""

# image.bbclass marks these noexec; SRC_URI needs them back.
do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# v1.3.3
SRCREV = "b858cb6936ab3ec653cbd54332fc1daa62f599a3"
SRC_URI += "git://gitlab.com/pantacor/pv-platforms/pvr-sdk;protocol=https;branch=master;destsuffix=sdk-src \
    file://pv-pvr-sdk.args.json \
    file://pv-pvr-sdk.config.json \
    file://pv-pvr-sdk-config \
    file://pv-pvr-sdk-start.sh \
    file://0001-pvr-auto-follow-fix-shell-syntax-errors.patch;apply=no \
"

# image.bbclass wipes ${S} at the start of do_rootfs, so the checkout lives
# beside it.
SDK_SRC = "${WORKDIR}/sdk-src"

PV_CONFIG_OVERLAY_DIR = "pv-pvr-sdk-config"

# Alpine's `adduser -g` sets the GECOS field, so pantavisor gets its own group.
# root lives in /root, where pv-user-meta-sync writes authorized_keys. Both
# accounts keep the SDK's documented default password (`pantabox`); change it
# with `passwd`. Nothing persists it across container restarts any more: that
# was pantabox's boot script, part of the TUI.
EXTRA_USERS_PARAMS = "\
    useradd -m -s /bin/sh pantavisor; \
    usermod -d /root root; \
    usermod -p '\$6\$pvrsdksalt\$qM3/4lhtx.8G.0hXIPTh.AUJDLUNUJsS8R/qvv6E05unJtxYssmb1acUzRPAtEqCYnca7/5QrV2hVcDAwLTYD.' root; \
    usermod -p '\$6\$pvrsdksalt\$qM3/4lhtx.8G.0hXIPTh.AUJDLUNUJsS8R/qvv6E05unJtxYssmb1acUzRPAtEqCYnca7/5QrV2hVcDAwLTYD.' pantavisor; \
"

install_sdk() {
    # SDK_SRC is not ${S}, so the patch class does not apply it. It fixes
    # pvr-auto-follow, which does not parse at v1.3.3.
    patch -p1 -d ${SDK_SRC} -i ${WORKDIR}/0001-pvr-auto-follow-fix-shell-syntax-errors.patch

    # pvcontrol and JSON.sh come from the pantavisor-pvcontrol / json-sh packages,
    # which container-pvrexport installs; the SDK's own copies are older forks.
    # The syslog bits configure a daemon this image does not carry,
    # /etc/resolv.conf is bind-mounted by lxc, and tmux.conf belongs to the
    # pantabox TUI, which is left out (files_pantabox is not installed at all).
    (cd ${SDK_SRC}/files && tar -c \
        --exclude=./usr/bin/pvcontrol --exclude=./usr/bin/JSON.sh \
        --exclude=./etc/init.d --exclude=./etc/conf.d \
        --exclude=./etc/logrotate.d --exclude=./logrotate.conf \
        --exclude=./etc/resolv.conf --exclude=./etc/tmux.conf .) | tar -x --no-same-owner -C ${IMAGE_ROOTFS}

    install -m 0755 ${WORKDIR}/pv-pvr-sdk-start.sh ${IMAGE_ROOTFS}${bindir}/pv-pvr-sdk-start

    # The pvtx CGI scripts call the static build as `pvtx`.
    ln -sf pvtx-static ${IMAGE_ROOTFS}${bindir}/pvtx

    install -d -m 0755 ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d
    echo "pantavisor ALL=(ALL) ALL" > ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d/pantavisor
    chmod 0440 ${IMAGE_ROOTFS}${sysconfdir}/sudoers.d/pantavisor

    # Mountpoints for the volumes below.
    install -d -m 0700 ${IMAGE_ROOTFS}/root/.ssh
    install -d -m 0700 ${IMAGE_ROOTFS}/home/pantavisor/.ssh
    install -d ${IMAGE_ROOTFS}${sysconfdir}/dropbear
    install -d ${IMAGE_ROOTFS}/var/pvr-sdk ${IMAGE_ROOTFS}/var/dmcrypt/volume
    install -d ${IMAGE_ROOTFS}/workspace

    install -d ${IMAGE_ROOTFS}${datadir}/doc/pvr-sdk
    install -m 0644 ${SDK_SRC}/LICENSE ${IMAGE_ROOTFS}${datadir}/doc/pvr-sdk/LICENSE

    echo "${PN}" > ${IMAGE_ROOTFS}${sysconfdir}/hostname
    sed -i "s/^127.0.1.1.*/127.0.1.1 ${PN}/" ${IMAGE_ROOTFS}${sysconfdir}/hosts
}
ROOTFS_POSTPROCESS_COMMAND += "install_sdk; "

# The SDK is a management container: pvpkg.json ships it as group platform,
# role mgmt, and no mdev rules.
PVR_APP_ADD_GROUP = "platform"
PVR_APP_ADD_ROLES = "mgmt"
PVRIMAGE_AUTO_MDEV = "0"

# `+=` discards the class's ??= default, so /var is restated. The rest are the
# Dockerfile's VOLUMEs; the last is pvpkg.json's dm-crypt volume.
PVR_APP_ADD_EXTRA_ARGS += " \
    --volume ovl:/var:permanent \
    --volume /home/pantavisor/.ssh:permanent \
    --volume /etc/dropbear:permanent \
    --volume /var/dmcrypt/volume:permanent@dm-versatile \
"

# Sign including config (override the --noconfig default from container-pvrexport)
PVR_SIG_ADD_ARGS = "--part ${PN}"

# do_deploy hook for pvroot-image consumption is provided by container-pvrexport
