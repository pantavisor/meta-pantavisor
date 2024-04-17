DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantavisor"
HOMEPAGE = "https://golang.org/"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "git://${GO_IMPORT};branch=bugfix/no-fakeroot-if-root;protocol=https"
SRCREV = "a16c7df04375b4cc15fc1eecba811fcfdc95b3dd"
UPSTREAM_CHECK_COMMITS = "1"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

CGO_ENABLED = "0"

inherit go-mod native

do_compile[network] = "1"

BBCLASSEXTEND = "native nativesdk"
