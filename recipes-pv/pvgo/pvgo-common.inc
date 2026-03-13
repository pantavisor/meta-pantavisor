SUMMARY = "Go programming language compiler (pvgo)"
DESCRIPTION = "Isolated Go toolchain for Pantavisor. \
This is completely separate from Poky's default Go recipes."
HOMEPAGE = "http://golang.org/"
LICENSE = "BSD-3-Clause"

# =============================================================
# Go version - update this single line to bump the Go version
# =============================================================
PV = "1.24.13"

inherit goarch

SRC_URI = "https://golang.org/dl/go${PV}.src.tar.gz;name=main"
S = "${WORKDIR}/go"
B = "${S}"
UPSTREAM_CHECK_REGEX = "(?P<pver>\d+(\.\d+)+)\.src\.tar"

CVE_PRODUCT = "golang:go"

INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
SSTATE_SCAN_CMD = "true"

export GOROOT_OVERRIDE = "1"
export GOTMPDIR ?= "${WORKDIR}/build-tmp"
GOTMPDIR[vardepvalue] = ""
export CGO_ENABLED = "1"

export GOHOSTOS ?= "${BUILD_GOOS}"
export GOHOSTARCH ?= "${BUILD_GOARCH}"

# Bootstrap from pvgo-bootstrap-native (Go 1.22.12), not Poky's go
export GOROOT_BOOTSTRAP ?= "${STAGING_LIBDIR_NATIVE}/pvgo-bootstrap"

export GOOS ?= "${TARGET_GOOS}"
export GOARCH ?= "${TARGET_GOARCH}"
export GOARM ?= "${TARGET_GOARM}"
export GO386 ?= "${TARGET_GO386}"
export GOMIPS ?= "${TARGET_GOMIPS}"
export GOROOT_FINAL ?= "${libdir}/pvgo"

export GODEBUG = "gocachehash=1"

do_compile:prepend() {
	BUILD_CC=${BUILD_CC}
}
