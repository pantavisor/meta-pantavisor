# agentic-app-skeleton.inc — included by every product agent-app recipe.
#
# A product container becomes an agent-app by:
#   1. `require recipes-containers/agentic/agentic-app-skeleton.inc`
#   2. Setting AGENTIC_APP_NAME = "<product>"
#   3. Adding `file://${AGENTIC_APP_NAME}.system_prompt.md`,
#      `file://${AGENTIC_APP_NAME}.tools.json`, and
#      `file://${AGENTIC_APP_NAME}.tools.py` to SRC_URI
#   4. Adding `file://${AGENTIC_APP_NAME}.config.json` (or relying on the
#      default written by this include).
#
# The skeleton library + the /usr/bin/agentic-app entrypoint come from
# the agentic-app-skeleton recipe, pulled in via IMAGE_INSTALL.

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

PVRIMAGE_AUTO_MDEV = "0"
IMAGE_INSTALL += "agentic-app-skeleton python3-core python3-json python3-netserver python3-logging python3-threading busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# AGENTIC_APP_NAME defaults to recipe PN — products that follow the
# agentic-<product> naming convention need not override it.
AGENTIC_APP_NAME ??= "${PN}"

install_agentic_app_files() {
    install -d ${IMAGE_ROOTFS}/etc/agentic-app
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.system_prompt.md \
        ${IMAGE_ROOTFS}/etc/agentic-app/system_prompt.md
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.tools.json \
        ${IMAGE_ROOTFS}/etc/agentic-app/tools.json
    if [ -f "${WORKDIR}/${AGENTIC_APP_NAME}.config.json" ]; then
        install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.config.json \
            ${IMAGE_ROOTFS}/etc/agentic-app/config.json
    fi
    install -d ${IMAGE_ROOTFS}/usr/lib/agentic-app
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.tools.py \
        ${IMAGE_ROOTFS}/usr/lib/agentic-app/tools.py
}

ROOTFS_POSTPROCESS_COMMAND += "install_agentic_app_files; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/agentic-app"
PVR_APP_ADD_GROUP ??= "platform"
