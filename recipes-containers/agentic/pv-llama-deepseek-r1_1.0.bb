SUMMARY = "pv-llama-deepseek-r1 — on-device DeepSeek-R1-Distill-Qwen-1.5B via llama.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-llama-deepseek-r1"
PVRIMAGE_AUTO_MDEV = "0"

# llama.cpp ships the HTTP server; the rest is just a launcher. Model is
# baked in via SRC_URI, so no curl / ca-certs are needed at runtime.
IMAGE_INSTALL += "llama-cpp socat busybox"

do_fetch[noexec] = "0"
do_unpack[noexec] = "0"

# DeepSeek-R1-Distill-Qwen-1.5B, Q4_K_M quantisation (~1.1 GB). Bitbake
# fetches and caches it in DL_DIR at build time; no runtime download.
#
# To bump the model: change DEEPSEEK_MODEL_URL and DEEPSEEK_MODEL_SHA256
# (grab the SHA with `curl -sL <url> | sha256sum`).
DEEPSEEK_MODEL_URL ?= "https://huggingface.co/unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
DEEPSEEK_MODEL_SHA256 ?= "f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840"
DEEPSEEK_MODEL_NAME ?= "deepseek.gguf"

SRC_URI += "file://pv-llama-deepseek-r1-run.sh \
            file://${PN}.services.json \
            ${DEEPSEEK_MODEL_URL};name=model;downloadfilename=${DEEPSEEK_MODEL_NAME};unpack=0"

SRC_URI[model.sha256sum] = "${DEEPSEEK_MODEL_SHA256}"

MODEL_INSTALL_DIR = "${datadir}/pv-llama-deepseek-r1"

install_scripts() {
    install -d ${IMAGE_ROOTFS}${bindir}
    install -m 0755 ${WORKDIR}/pv-llama-deepseek-r1-run.sh ${IMAGE_ROOTFS}${bindir}/pv-llama-deepseek-r1-run

    install -d ${IMAGE_ROOTFS}${MODEL_INSTALL_DIR}
    install -m 0644 ${WORKDIR}/${DEEPSEEK_MODEL_NAME} ${IMAGE_ROOTFS}${MODEL_INSTALL_DIR}/${DEEPSEEK_MODEL_NAME}
}

ROOTFS_POSTPROCESS_COMMAND += "install_scripts; "

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-llama-deepseek-r1-run"
