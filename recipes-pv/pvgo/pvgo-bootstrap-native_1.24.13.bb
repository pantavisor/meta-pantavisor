# Bootstrap recipe for pvgo build chain.
# Downloads a pre-built Go 1.24.13 binary to bootstrap Go 1.26 from source.
# Go 1.26 requires Go 1.24.6+ for bootstrap.

SUMMARY = "Go programming language compiler (binary bootstrap for pvgo)"
HOMEPAGE = "http://golang.org/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=7998cb338f82d15c0eff93b7004d272a"

PROVIDES = "pvgo-bootstrap-native"

# Checksums from https://go.dev/dl/
SRC_URI = "https://dl.google.com/go/go${PV}.${BUILD_GOOS}-${BUILD_GOARCH}.tar.gz;name=go_${BUILD_GOTUPLE}"
SRC_URI[go_linux_amd64.sha256sum] = "1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730"
SRC_URI[go_linux_arm64.sha256sum] = "74d97be1cc3a474129590c67ebf748a96e72d9f3a2b6fef3ed3275de591d49b3"
SRC_URI[go_linux_ppc64le.sha256sum] = "5f0dfab58ce15a84d824363c041246c76847a69d14f9ffac16bd5342299ecc14"

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
