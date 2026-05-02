SUMMARY = "llama-swap — on-demand model-swapping reverse proxy for llama.cpp"
DESCRIPTION = "OpenAI-compatible HTTP proxy that lazily spawns and swaps \
llama-server backends per request. Used by pv-llama as the multi-model \
front door so a single endpoint exposes every local GGUF and routes \
each request's `model` field to the right backend, swapping models in \
and out under a configurable RAM budget."
HOMEPAGE = "https://github.com/mostlygeek/llama-swap"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE.md;md5=1ee2ee9408fd04e9cf7f852aa9069155"

# llama-swap upstream pins go 1.26 which is newer than what scarthgap
# ships (1.22), and the binary is pure Go with CGO disabled, so just
# install the upstream-published static release. Bumping = change PV
# and update both sha256 entries.
PV = "207"

LSWAP_ARCH = "INVALID"
LSWAP_ARCH:aarch64 = "arm64"
LSWAP_ARCH:x86-64 = "amd64"

SRC_URI = "https://github.com/mostlygeek/llama-swap/releases/download/v${PV}/llama-swap_${PV}_linux_${LSWAP_ARCH}.tar.gz;name=${LSWAP_ARCH}"

SRC_URI[arm64.sha256sum] = "f1c3e0127d82e166f092972535d19f13ab0724fea8217402843d48a53566f0d1"
SRC_URI[amd64.sha256sum] = "bc08190695b0ac5ca2142ca3f0484b371d406fae9915ac8f62c8ff0e386b360c"

COMPATIBLE_HOST = "(aarch64|x86_64).*-linux"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${S}/llama-swap ${D}${bindir}/llama-swap
}

FILES:${PN} = "${bindir}/llama-swap"

# Upstream binary is statically linked Go; standard Yocto QA checks
# don't apply.
INSANE_SKIP:${PN} += "ldflags already-stripped arch textrel"
