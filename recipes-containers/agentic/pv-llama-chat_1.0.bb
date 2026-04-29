SUMMARY = "pv-llama-chat — minimal browser chat UI for pv-llama with completion monitor"
DESCRIPTION = "Tiny Python HTTP server + single-page web UI. Acts as an \
xconnect consumer of pv-llama (its OpenAI-compatible UDS) and exposes a \
browser-friendly chat over TCP plus a live `/api/monitor` SSE feed of all \
recent completions. Useful for trying models interactively and watching what \
agent-apps in the same image are sending to the model in real time."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "${PN}"
PVRIMAGE_AUTO_MDEV = "0"

# python3-netserver gives us http.server; the rest are deps the
# server.py module imports directly.
IMAGE_INSTALL += "python3-core python3-json python3-netserver \
                  python3-threading python3-logging busybox"

# container-pvrexport.bbclass auto-appends `pvcontrol` to IMAGE_INSTALL.
# Under the rpi-tryboot multi-arch machine, container userspace is built
# as arm1176jzfshf_vfp (lowest-common-denominator) but pantavisor's
# `pvcontrol` subpackage is only assembled for the BSP arch (cortexa53),
# so dnf can't resolve it. This container doesn't actually need to
# script pvr/pvcontrol from inside, so drop it.
IMAGE_INSTALL:remove = "pvcontrol"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

SRC_URI += "file://pv-llama-chat-run.sh \
            file://server.py \
            file://index.html \
            file://${PN}.args.json"

# Bind port for the chat UI. Default 8080 — exposing it on the device
# is a deployment decision (host networking, port forward, or an
# xconnect REST provider in front). Override at recipe time if needed.
PV_LLAMA_CHAT_PORT ??= "12345"

install_pv_llama_chat() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-llama-chat-run.sh \
        ${IMAGE_ROOTFS}${bindir}/pv-llama-chat

    install -d ${IMAGE_ROOTFS}/usr/lib/pv-llama-chat
    install -m 0644 ${WORKDIR}/server.py \
        ${IMAGE_ROOTFS}/usr/lib/pv-llama-chat/server.py
    install -m 0644 ${WORKDIR}/index.html \
        ${IMAGE_ROOTFS}/usr/lib/pv-llama-chat/index.html

    # Bake the configured port into the entrypoint via a small env file
    # the entrypoint sources. Avoids sed-on-script hackery and keeps
    # the script itself a static, reviewable file.
    install -d ${IMAGE_ROOTFS}${sysconfdir}/pv-llama-chat
    cat > ${IMAGE_ROOTFS}${sysconfdir}/pv-llama-chat/env <<EOF
PV_LLAMA_CHAT_PORT=${PV_LLAMA_CHAT_PORT}
PV_LLAMA_UDS=/run/pv/services/pv-llama.sock
EOF
    chmod 0644 ${IMAGE_ROOTFS}${sysconfdir}/pv-llama-chat/env
}

ROOTFS_POSTPROCESS_COMMAND += "install_pv_llama_chat; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-llama-chat"
