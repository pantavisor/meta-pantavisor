DEPENDS = "virtual/${TUNE_PKGARCH}-pvgo pvgo-bootstrap-native"
DEPENDS:class-nativesdk = "virtual/${TARGET_PREFIX}pvgo"
PROVIDES = "virtual/${TARGET_PREFIX}pvgo-runtime"

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

GO_EXTLDFLAGS ?= "${HOST_CC_ARCH}${TOOLCHAIN_OPTIONS} ${LDFLAGS}"
GO_SHLIB_LDFLAGS ?= '-ldflags="-extldflags '${GO_EXTLDFLAGS}'"'

do_configure() {
	:
}

do_configure:libc-musl() {
	rm -f ${S}/src/runtime/race/*.syso
}

do_compile() {
	export CC_FOR_${TARGET_GOTUPLE}="${CC}"
	export CXX_FOR_${TARGET_GOTUPLE}="${CXX}"

	cd src
	./make.bash --no-banner
	cd ${B}
}
do_compile[cleandirs] += "${GOTMPDIR} ${B}/bin ${B}/pkg"

do_install() {
	install -d ${D}${libdir}/pvgo/src
	cp --preserve=mode,timestamps -R ${B}/pkg ${D}${libdir}/pvgo/
	if [ "${BUILD_GOTUPLE}" != "${TARGET_GOTUPLE}" ]; then
		rm -rf ${D}${libdir}/pvgo/pkg/${BUILD_GOTUPLE}
		rm -rf ${D}${libdir}/pvgo/pkg/obj/${BUILD_GOTUPLE}
	fi
	rm -rf ${D}${libdir}/pvgo/pkg/tool
	rm -rf ${D}${libdir}/pvgo/pkg/obj
	rm -rf ${D}${libdir}/pvgo/pkg/bootstrap
	rm -rf ${D}${libdir}/pvgo/pkg/${BUILD_GOTUPLE}/cmd
	find src -mindepth 1 -maxdepth 1 -type d | while read srcdir; do
		cp --preserve=mode,timestamps -R $srcdir ${D}${libdir}/pvgo/src/
	done
	find ${D}${libdir}/pvgo/src -depth -type d -name testdata -exec rm -rf {} \;
	rm -f ${D}${libdir}/pvgo/src/cmd/dist/dist
        rm -f ${D}${libdir}/pvgo/src/cmd/cgo/zdefaultcc.go
        rm -f ${D}${libdir}/pvgo/src/cmd/go/internal/cfg/zdefaultcc.go

}

ALLOW_EMPTY:${PN} = "1"
FILES:${PN} = "${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*${SOLIBSDEV}"
FILES:${PN}-dev = "${libdir}/pvgo/src ${libdir}/pvgo/pkg/include \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*/*/*.shlibname \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*/*.a \
                   ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink/*/*/*/*/*/*/*.a \
"
FILES:${PN}-staticdev = "${libdir}/pvgo/pkg/${TARGET_GOTUPLE}"

INSANE_SKIP:${PN}-dev = "staticdev file-rdeps arch"

INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"

BBCLASSEXTEND = "nativesdk"
