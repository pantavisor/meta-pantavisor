inherit cross

PROVIDES = "virtual/${TUNE_PKGARCH}-pvgo"
DEPENDS = "pvgo-bootstrap-native"

PN = "pvgo-cross-${TUNE_PKGARCH}"

export GOCACHE = "${B}/.cache"
CC = "${@d.getVar('BUILD_CC').strip()}"

do_configure[noexec] = "1"

do_compile() {
	export CC_FOR_${TARGET_GOTUPLE}="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} --sysroot=${STAGING_DIR_TARGET}"
	export CXX_FOR_${TARGET_GOTUPLE}="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} --sysroot=${STAGING_DIR_TARGET}"
	export CGO_ENABLED=0
	cd src
	./make.bash --no-banner
	cd ${B}
}
do_compile[cleandirs] += "${GOTMPDIR} ${B}/bin ${B}/pkg"

make_wrapper() {
	rm -f ${D}${bindir}/$2
	cat <<END >${D}${bindir}/$2
#!/bin/bash
here=\`dirname \$0\`
export GOARCH="${TARGET_GOARCH}"
export GOOS="${TARGET_GOOS}"
export GOARM="\${GOARM:-${TARGET_GOARM}}"
export GO386="\${GO386:-${TARGET_GO386}}"
export GOMIPS="\${GOMIPS:-${TARGET_GOMIPS}}"
\$here/../../lib/${CROSS_TARGET_SYS_DIR}/pvgo/bin/$1 "\$@"
END
	chmod +x ${D}${bindir}/$2
}

do_install() {
	install -d ${D}${libdir}/pvgo
	cp --preserve=mode,timestamps -R ${B}/pkg ${D}${libdir}/pvgo/
	install -d ${D}${libdir}/pvgo/src
	(cd ${S}/src; for d in *; do \
		[ ! -d $d ] || cp --preserve=mode,timestamps -R ${S}/src/$d ${D}${libdir}/pvgo/src/; \
	done)
	find ${D}${libdir}/pvgo/src -depth -type d -name testdata -exec rm -rf {} \;
	install -d ${D}${bindir} ${D}${libdir}/pvgo/bin
	install -m755 ${B}/bin/go ${D}${libdir}/pvgo/bin
	make_wrapper go ${TARGET_PREFIX}pvgo
	if [ -f ${B}/bin/gofmt ]; then
		install -m755 ${B}/bin/gofmt ${D}${libdir}/pvgo/bin
		make_wrapper gofmt ${TARGET_PREFIX}pvgo-fmt
	fi
}

INHIBIT_SYSROOT_STRIP = "1"
