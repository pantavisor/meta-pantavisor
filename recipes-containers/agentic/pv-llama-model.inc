# Shared bits for pv-llama-model-<name> recipes.
#
# Each model recipe fetches one GGUF and packages it (plus a tiny
# manifest) into a single read-only squashfs. The squashfs is exposed
# in the recipe sysroot under ${datadir}/pv-llama/models/<name>.squashfs
# so the pv-llama container recipe can DEPENDS on it and copy it into
# the staged container directory as its own pvr object.
#
# A per-model recipe only has to set:
#   LLAMA_MODEL_NAME      - short id, e.g. "qwen", "deepseek-r1"
#   LLAMA_MODEL_URL       - full URL of the GGUF
#   LLAMA_MODEL_SHA256    - sha256 of that file
#   LLAMA_MODEL_VERSION   - free-form version label baked into model.json
#   LLAMA_MODEL_DESC      - one-line human description for model.json
# Optional:
#   LLAMA_MODEL_FAMILY    - e.g. "qwen2", "deepseek-r1" (default: name)
#   LLAMA_MODEL_PARAMS    - e.g. "0.5B", "1.5B"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

DEPENDS = "squashfs-tools-native"

LLAMA_MODEL_FAMILY ??= "${LLAMA_MODEL_NAME}"
LLAMA_MODEL_PARAMS ??= ""
LLAMA_MODEL_FILE ??= "model.gguf"

SRC_URI = "${LLAMA_MODEL_URL};name=model;downloadfilename=${LLAMA_MODEL_NAME}.gguf;unpack=0"
SRC_URI[model.sha256sum] = "${LLAMA_MODEL_SHA256}"

S = "${WORKDIR}"

do_compile() {
    local stage="${WORKDIR}/squash-stage"
    rm -rf "$stage"
    mkdir -p "$stage"
    install -m 0644 ${WORKDIR}/${LLAMA_MODEL_NAME}.gguf "$stage/${LLAMA_MODEL_FILE}"
    # Indented to keep no line at column 0 starting with '}' — bitbake's
    # shell-function parser treats `^}` as end-of-function, even inside
    # a heredoc, and would silently truncate this task otherwise.
    cat > "$stage/model.json" <<EOF
        {
          "name": "${LLAMA_MODEL_NAME}",
          "family": "${LLAMA_MODEL_FAMILY}",
          "params": "${LLAMA_MODEL_PARAMS}",
          "version": "${LLAMA_MODEL_VERSION}",
          "description": "${LLAMA_MODEL_DESC}",
          "file": "${LLAMA_MODEL_FILE}",
          "sha256": "${LLAMA_MODEL_SHA256}"
        }
EOF

    rm -f ${WORKDIR}/${LLAMA_MODEL_NAME}.squashfs
    mksquashfs "$stage" ${WORKDIR}/${LLAMA_MODEL_NAME}.squashfs \
        -comp xz -reproducible -no-progress

    rm -rf "$stage"
}

do_install() {
    install -d ${D}${datadir}/pv-llama/models
    install -m 0644 ${WORKDIR}/${LLAMA_MODEL_NAME}.squashfs \
        ${D}${datadir}/pv-llama/models/${LLAMA_MODEL_NAME}.squashfs
}

# The squashfs is consumed at build time by the pv-llama container
# recipe via the sysroot — no runtime package output needed.
SYSROOT_DIRS += "${datadir}/pv-llama"

PACKAGES = ""
