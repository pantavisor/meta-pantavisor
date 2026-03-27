# Pre-built Go 1.24.13 binary for native use.
# Provides pvgo-native so that native recipes (e.g. pvr-native) use Go 1.24.

SUMMARY = "Go programming language compiler (pre-built binary for pvgo)"
HOMEPAGE = "http://golang.org/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=7998cb338f82d15c0eff93b7004d272a"

PROVIDES = "pvgo-native"

# Checksums from https://go.dev/dl/
SRC_URI = "https://dl.google.com/go/go${PV}.${BUILD_GOOS}-${BUILD_GOARCH}.tar.gz;name=go_${BUILD_GOTUPLE}"
SRC_URI[go_linux_amd64.sha256sum] = "1fc94b57134d51669c72173ad5d49fd62afb0f1db9bf3f798fd98ee423f8d730"
SRC_URI[go_linux_arm64.sha256sum] = "c73a430388d8958d6db65bb2b1ef17581f9f9a4bcf4e7206dc891cbba89fff4b"
SRC_URI[go_linux_ppc64le.sha256sum] = "3cb96891c877c9997d2a58c2c1a0823afeff96b1fc6184bafdbd957be8d52265"

UPSTREAM_CHECK_URI = "https://golang.org/dl/"
UPSTREAM_CHECK_REGEX = "go(?P<pver>\d+(\.\d+)+)\.linux"

CVE_PRODUCT = "golang:go"

S = "${WORKDIR}/go"

inherit goarch native

do_compile() {
    :
}

make_wrapper() {
	# $1 = original binary name (e.g. "go"), $2 = wrapper name (e.g. "pvgo")
	rm -f ${D}${bindir}/$2
	cat <<END >${D}${bindir}/$2
#!/bin/bash
here=\`dirname \$0\`
export GOROOT="${GOROOT:-\`readlink -f \$here/../lib/pvgo\`}"
\$here/../lib/pvgo/bin/$1 "\$@"
END
	chmod +x ${D}${bindir}/$2
}

do_install() {
    find ${S} -depth -type d -name testdata -exec rm -rf {} +

	install -d ${D}${bindir} ${D}${libdir}/pvgo
	tar -C ${S} -cf - . | tar -C ${D}${libdir}/pvgo --no-same-owner -xf -

	make_wrapper go pvgo
	make_wrapper gofmt pvgo-fmt
}
