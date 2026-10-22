# Pre-built Go 1.26.10 binary for native use.
# Provides pvgo-native so that native recipes (e.g. pvr-native) use Go 1.26.

SUMMARY = "Go programming language compiler (pre-built binary for pvgo)"
HOMEPAGE = "http://golang.org/"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=7998cb338f82d15c0eff93b7004d272a"

PROVIDES = "pvgo-native"

# Checksums from https://go.dev/dl/
SRC_URI = "https://dl.google.com/go/go${PV}.${BUILD_GOOS}-${BUILD_GOARCH}.tar.gz;name=go_${BUILD_GOTUPLE}"
SRC_URI[go_linux_amd64.sha256sum] = "ccfe7ae822d2c2f41f4fe7c956199967a4dac22d0ee0d2b2bfdb440aab3b20c5"
SRC_URI[go_linux_arm64.sha256sum] = "3f4227ce7b206a513e794f1393adb473a07b46e94d18bd15d1c684bbb7319797"
SRC_URI[go_linux_ppc64le.sha256sum] = "4492031a19657de3bd7e4c48dce9d9e5aa7b668300f7c2c98e620b9ac0ee84ee"

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
