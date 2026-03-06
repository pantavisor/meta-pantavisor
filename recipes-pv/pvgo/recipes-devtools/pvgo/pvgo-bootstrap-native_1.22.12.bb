# Bootstrap recipe for pvgo build chain.
# Downloads a pre-built Go 1.22.12 binary to bootstrap Go 1.24 from source.
# Go 1.24 requires Go 1.22.6+ for bootstrap.

SUMMARY = "Go programming language compiler (binary bootstrap for pvgo)"
HOMEPAGE = "http://golang.org/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5d4950ecb7b26d2c5e4e7b4e0dd74707"

PROVIDES = "pvgo-bootstrap-native"

# Checksums from https://go.dev/dl/
SRC_URI = "https://dl.google.com/go/go${PV}.${BUILD_GOOS}-${BUILD_GOARCH}.tar.gz;name=go_${BUILD_GOTUPLE}"
SRC_URI[go_linux_amd64.sha256sum] = "4fa4f869b0f7fc6bb1eb2660e74657fbf04cdd290b5aef905585c86051b34d43"
SRC_URI[go_linux_arm64.sha256sum] = "fd017e647ec28525e86ae8203236e0653242722a7436929b1f775744e26278e7"
SRC_URI[go_linux_ppc64le.sha256sum] = "9573d30003b0796717a99d9e2e96c48fddd4fc0f29d840f212c503b03d7de112"

UPSTREAM_CHECK_URI = "https://golang.org/dl/"
UPSTREAM_CHECK_REGEX = "go(?P<pver>\d+(\.\d+)+)\.linux"

CVE_PRODUCT = "golang:go"

S = "${WORKDIR}/go"

inherit goarch native

do_compile() {
    :
}

do_install() {
    find ${S} -depth -type d -name testdata -exec rm -rf {} +

	install -d ${D}${libdir}/pvgo-bootstrap
	tar -C ${S} -cf - . | tar -C ${D}${libdir}/pvgo-bootstrap --no-same-owner -xf -
}
