# agentic-app-skeleton.inc — included by every product agent-app recipe.
#
# A product container becomes an agent-app by:
#   1. `require recipes-containers/agentic/agentic-app-skeleton.inc`
#   2. Setting AGENTIC_APP_NAME = "<product>"
#   3. Adding `file://${AGENTIC_APP_NAME}.system_prompt.md`,
#      `file://${AGENTIC_APP_NAME}.tools.json`, and
#      `file://${AGENTIC_APP_NAME}.tools.py` to SRC_URI
#   4. Optionally adding `file://${AGENTIC_APP_NAME}.runtime.json` to
#      override skeleton-shipped runtime defaults (deep-merged at runtime
#      over /etc/agentic-app/defaults.json).
#
# Recipe authors who want full ownership of every config layer can
# disable inheritance via:
#
#   AGENTIC_APP_DEFAULTS = ""        # no skeleton defaults at all
#   AGENTIC_APP_DEFAULTS:remove = "runtime"   # opt out of just one layer
#
# In that case ${AGENTIC_APP_NAME}.runtime.json (installed as
# /etc/agentic-app/config.json) becomes the single source of truth and
# must declare every key the runtime needs (llm, model, sink, etc.).
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

# AGENTIC_APP_DEFAULTS — space-separated list of skeleton-shipped default
# layers the app inherits. Set to the empty string to opt fully out and
# let ${AGENTIC_APP_NAME}.runtime.json (or its peers) be the single source
# of truth. Recognised entries:
#   runtime    inherit /etc/agentic-app/defaults.json (LLM UDS, model,
#              timeout, sink, max_iterations). Removed at install time
#              when not listed, so the runtime sees no defaults to merge.
# When more skeleton-shipped default layers are added (e.g. tools), they
# follow the same opt-in/opt-out pattern via this variable.
AGENTIC_APP_DEFAULTS ??= "runtime"

install_agentic_app_files() {
    install -d ${IMAGE_ROOTFS}/etc/agentic-app
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.system_prompt.md \
        ${IMAGE_ROOTFS}/etc/agentic-app/system_prompt.md
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.tools.json \
        ${IMAGE_ROOTFS}/etc/agentic-app/tools.json
    # Optional per-app overrides. The skeleton ships
    # /etc/agentic-app/defaults.json with mesh-constant values (LLM UDS,
    # default model, timeout, iteration cap, default sink), so most apps
    # only need to declare `feeds` and any app-specific overrides here.
    # The runtime deep-merges config.json over defaults.json.
    #
    # Filename note: this file is `.runtime.json`, NOT `.config.json` —
    # `${PN}.config.json` is auto-consumed by container-pvrexport.bbclass
    # as the Docker-style image config, which would collide with the
    # agent-app's runtime config. The different suffix keeps pvrexport
    # out of it; the file still lands as /etc/agentic-app/config.json
    # where the runtime expects it.
    if [ -f "${WORKDIR}/${AGENTIC_APP_NAME}.runtime.json" ]; then
        install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.runtime.json \
            ${IMAGE_ROOTFS}/etc/agentic-app/config.json
    fi
    install -d ${IMAGE_ROOTFS}/usr/lib/agentic-app
    install -m 0644 ${WORKDIR}/${AGENTIC_APP_NAME}.tools.py \
        ${IMAGE_ROOTFS}/usr/lib/agentic-app/tools.py

    # AGENTIC_APP_DEFAULTS opt-outs: if the per-app recipe does not list
    # 'runtime', strip the skeleton-shipped defaults.json so the runtime
    # has nothing to merge and only ${AGENTIC_APP_NAME}.runtime.json
    # (installed as config.json above) is in force.
    if ! echo " ${AGENTIC_APP_DEFAULTS} " | grep -qw runtime; then
        rm -f ${IMAGE_ROOTFS}/etc/agentic-app/defaults.json
    fi
}

ROOTFS_POSTPROCESS_COMMAND += "install_agentic_app_files; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/agentic-app"
PVR_APP_ADD_GROUP ??= "platform"
