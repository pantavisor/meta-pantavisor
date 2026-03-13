DEPENDS = "virtual/${TUNE_PKGARCH}-pvgo pvgo-bootstrap-native"
DEPENDS:class-nativesdk = "virtual/${TARGET_PREFIX}pvgo pvgo-bootstrap-native"

DEBUG_PREFIX_MAP = "\
                     -fdebug-prefix-map=${STAGING_DIR_HOST}= \
                     -fdebug-prefix-map=${STAGING_DIR_NATIVE}= \
"

export CGO_CFLAGS = "${CFLAGS}"
export CGO_CPPFLAGS = "${CPPFLAGS}"
export CGO_CXXFLAGS = "${CXXFLAGS}"
# Filter out -fdebug-prefix-map options as they clash with the GO's build system
export CGO_LDFLAGS = "${@ ' '.join(filter(lambda f: not f.startswith('-fdebug-prefix-map'), d.getVar('LDFLAGS').split())) }"

export GOCACHE = "${B}/.cache"
export GO_LDFLAGS = ""
export GOBUILDFLAGS = "-gcflags=-trimpath=$GOPATH -asmflags=-trimpath=$GOPATH -trimpath"
CC:append:class-nativesdk = " ${SECURITY_NOPIE_CFLAGS}"

do_configure[noexec] = "1"

do_compile() {
	export CC_FOR_${TARGET_GOOS}_${TARGET_GOARCH}="${CC}"
	export CXX_FOR_${TARGET_GOOS}_${TARGET_GOARCH}="${CXX}"

	cd src
	./make.bash --no-banner
	cd ${B}
}
do_compile[cleandirs] += "${GOTMPDIR} ${B}/bin ${B}/pkg"

do_install() {
	install -d ${D}${libdir}/pvgo/pkg/tool
	cp --preserve=mode,timestamps -R ${B}/pkg/tool/${TARGET_GOTUPLE} ${D}${libdir}/pvgo/pkg/tool/
	install -d ${D}${libdir}/pvgo/src
	cp --preserve=mode,timestamps -R ${S}/src/cmd ${D}${libdir}/pvgo/src/
	find ${D}${libdir}/pvgo/src -depth -type d -name testdata -exec rm -rf {} \;
	install -d ${D}${libdir}/pvgo/bin
	install -d ${D}${bindir}
	for f in ${B}/${GO_BUILD_BINDIR}/*; do
		name=`basename $f`
		install -m 0755 $f ${D}${libdir}/pvgo/bin/
		ln -sf ../${baselib}/pvgo/bin/$name ${D}${bindir}/
	done
	rm -rf ${D}${libdir}/pvgo/src
}

PACKAGES = "${PN} ${PN}-dev"
FILES:${PN} = "${libdir}/pvgo/bin ${libdir}/pvgo/pkg/tool/${TARGET_GOTUPLE} ${bindir}"
RDEPENDS:${PN} = "pvgo-runtime"
INSANE_SKIP:${PN} = "ldflags"

BBCLASSEXTEND = "nativesdk"
