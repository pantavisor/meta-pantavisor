SUMMARY = "llama.cpp — LLM inference in C/C++ with OpenAI-compatible HTTP server"
HOMEPAGE = "https://github.com/ggml-org/llama.cpp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=1539dadbedb60aa18519febfeab70632"

SRC_URI = "gitsm://github.com/ggml-org/llama.cpp;protocol=https;branch=master"

# b4600 (pin a known-good tag; bump as needed). Must be >= b4514 for
# DeepSeek-R1-Qwen distill tokenizer support (added in commit ec7f3ac9
# on 2025-01-20).
SRCREV = "553f1e46e9e864514bbd6bf4009146db66be0541"
PV = "0.0+git${SRCPV}"

S = "${WORKDIR}/git"

DEPENDS = "curl openssl"

inherit cmake pkgconfig

# CPU-only build; keep the image lean. Turn off every accelerator backend
# and every example except the HTTP server.
EXTRA_OECMAKE = " \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=ON \
    -DLLAMA_CURL=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_BLAS=OFF \
    -DGGML_CUDA=OFF \
    -DGGML_HIP=OFF \
    -DGGML_VULKAN=OFF \
    -DGGML_METAL=OFF \
    -DGGML_OPENMP=ON \
    -DGGML_LTO=ON \
    -DBUILD_SHARED_LIBS=OFF \
"

# aarch64 / armv7 don't benefit from -march=native and Yocto already sets
# the correct tuning flags via TUNE_CCARGS.
TARGET_CC_ARCH += "${LDFLAGS}"

do_install:append() {
    # Older trees may not install llama-server in a standard location.
    if [ -x ${B}/bin/llama-server ] && [ ! -x ${D}${bindir}/llama-server ]; then
        install -d ${D}${bindir}
        install -m 0755 ${B}/bin/llama-server ${D}${bindir}/llama-server
    fi
}

FILES:${PN} += "${bindir}/llama-server"

# Embedded-friendly: no debug split surprises from stripped static builds.
INSANE_SKIP:${PN} += "ldflags"
