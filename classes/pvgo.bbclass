#
# pvgo.bbclass - Isolated Go build class for Pantavisor
#
# This class provides Go build support completely isolated from
# Poky's default Go recipes. Packages inheriting this class will always
# use the pvgo-provided Go regardless of what other layers configure.
#
# SPDX-License-Identifier: MIT
#

inherit goarch
inherit linuxloader

GO_PARALLEL_BUILD ?= "${@oe.utils.parallel_make_argument(d, '-p %d')}"

export GODEBUG = "gocachehash=1"

GOROOT:class-native = "${STAGING_LIBDIR_NATIVE}/pvgo"
GOROOT:class-nativesdk = "${STAGING_DIR_TARGET}${libdir}/pvgo"
GOROOT = "${STAGING_LIBDIR_NATIVE}/${TARGET_SYS}/pvgo"
export GOROOT
export GOROOT_FINAL = "${libdir}/pvgo"
export GOCACHE = "${B}/.cache"

export GOARCH = "${TARGET_GOARCH}"
export GOOS = "${TARGET_GOOS}"
export GOHOSTARCH="${BUILD_GOARCH}"
export GOHOSTOS="${BUILD_GOOS}"

GOARM[export] = "0"
GOARM:arm:class-target = "${TARGET_GOARM}"
GOARM:arm:class-target[export] = "1"

GO386[export] = "0"
GO386:x86:class-target = "${TARGET_GO386}"
GO386:x86:class-target[export] = "1"

GOMIPS[export] = "0"
GOMIPS:mips:class-target = "${TARGET_GOMIPS}"
GOMIPS:mips:class-target[export] = "1"

# Isolated dependencies - use pvgo recipes instead of Poky's go
DEPENDS_GOLANG:class-target = "virtual/${TUNE_PKGARCH}-pvgo virtual/${TARGET_PREFIX}pvgo-runtime"
DEPENDS_GOLANG:class-native = "pvgo-native"
DEPENDS_GOLANG:class-nativesdk = "virtual/${TARGET_PREFIX}pvgo virtual/${TARGET_PREFIX}pvgo-runtime"

DEPENDS:append = " ${DEPENDS_GOLANG}"

GO_LINKSHARED ?= "${@'-linkshared' if d.getVar('GO_DYNLINK') else ''}"
GO_RPATH_LINK = "${@'-Wl,-rpath-link=${STAGING_DIR_TARGET}${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink' if d.getVar('GO_DYNLINK') else ''}"
GO_RPATH = "${@'-r ${libdir}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink' if d.getVar('GO_DYNLINK') else ''}"
GO_RPATH:class-native = "${@'-r ${STAGING_LIBDIR_NATIVE}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink' if d.getVar('GO_DYNLINK') else ''}"
GO_RPATH_LINK:class-native = "${@'-Wl,-rpath-link=${STAGING_LIBDIR_NATIVE}/pvgo/pkg/${TARGET_GOTUPLE}_dynlink' if d.getVar('GO_DYNLINK') else ''}"
GO_EXTLDFLAGS ?= "${HOST_CC_ARCH}${TOOLCHAIN_OPTIONS} ${GO_RPATH_LINK} ${LDFLAGS}"
GO_LINKMODE ?= ""
GO_EXTRA_LDFLAGS ?= ""
GO_LINUXLOADER ?= "-I ${@get_linuxloader(d)}"
GO_LINUXLOADER:class-native = ""
GO_LDFLAGS ?= '-ldflags="${GO_RPATH} ${GO_LINKMODE} ${GO_LINUXLOADER} ${GO_EXTRA_LDFLAGS} -extldflags '${GO_EXTLDFLAGS}'"'
export GOBUILDFLAGS ?= "-v ${GO_LDFLAGS} -trimpath"
export GOPATH_OMIT_IN_ACTIONID ?= "1"
export GOPTESTBUILDFLAGS ?= "${GOBUILDFLAGS} -c"
export GOPTESTFLAGS ?= ""
GOBUILDFLAGS:prepend:task-compile = "${GO_PARALLEL_BUILD} "

# Use isolated pvgo compiler
export GO = "${HOST_PREFIX}pvgo"
GOTOOLDIR = "${STAGING_LIBDIR_NATIVE}/${TARGET_SYS}/pvgo/pkg/tool/${BUILD_GOTUPLE}"
GOTOOLDIR:class-native = "${STAGING_LIBDIR_NATIVE}/pvgo/pkg/tool/${BUILD_GOTUPLE}"
export GOTOOLDIR

export CGO_ENABLED ?= "1"
export CGO_CFLAGS ?= "${CFLAGS}"
export CGO_CPPFLAGS ?= "${CPPFLAGS}"
export CGO_CXXFLAGS ?= "${CXXFLAGS}"
export CGO_LDFLAGS ?= "${LDFLAGS}"

GO_INSTALL ?= "${GO_IMPORT}/..."
GO_INSTALL_FILTEROUT ?= "${GO_IMPORT}/vendor/"

GO_BUILD_BINDIR ?= "bin"

B = "${WORKDIR}/build"
export GOPATH = "${B}"
export GOENV = "off"
export GOPROXY ??= "https://proxy.golang.org,direct"
export GOTMPDIR ?= "${WORKDIR}/build-tmp"
GOTMPDIR[vardepvalue] = ""

python pvgo_do_unpack() {
    src_uri = (d.getVar('SRC_URI') or "").split()
    if len(src_uri) == 0:
        return

    fetcher = bb.fetch2.Fetch(src_uri, d)
    for url in fetcher.urls:
        if fetcher.ud[url].type == 'git':
            if fetcher.ud[url].parm.get('destsuffix') is None:
                s_dirname = os.path.basename(d.getVar('S'))
                fetcher.ud[url].parm['destsuffix'] = os.path.join(s_dirname, 'src', d.getVar('GO_IMPORT')) + '/'
    fetcher.unpack(d.getVar('WORKDIR'))
}

pvgo_list_packages() {
	${GO} list -f '{{.ImportPath}}' ${GOBUILDFLAGS} ${GO_INSTALL} | \
		egrep -v '${GO_INSTALL_FILTEROUT}'
}

pvgo_list_package_tests() {
	${GO} list -f '{{.ImportPath}} {{.TestGoFiles}}' ${GOBUILDFLAGS} ${GO_INSTALL} | \
		grep -v '\[\]$' | \
		egrep -v '${GO_INSTALL_FILTEROUT}' | \
		awk '{ print $1 }'
}

pvgo_do_configure() {
	ln -snf ${S}/src ${B}/
}
do_configure[dirs] =+ "${GOTMPDIR}"

pvgo_do_compile() {
	export TMPDIR="${GOTMPDIR}"
	if [ -n "${GO_INSTALL}" ]; then
		if [ -n "${GO_LINKSHARED}" ]; then
			${GO} install ${GOBUILDFLAGS} `pvgo_list_packages`
			rm -rf ${B}/bin
		fi
		${GO} install ${GO_LINKSHARED} ${GOBUILDFLAGS} `pvgo_list_packages`
	fi
}
do_compile[dirs] =+ "${GOTMPDIR}"
do_compile[cleandirs] = "${B}/bin ${B}/pkg"

pvgo_do_install() {
	install -d ${D}${libdir}/pvgo/src/${GO_IMPORT}
	tar -C ${S}/src/${GO_IMPORT} -cf - --exclude-vcs --exclude '*.test' --exclude 'testdata' . | \
		tar -C ${D}${libdir}/pvgo/src/${GO_IMPORT} --no-same-owner -xf -
	tar -C ${B} -cf - --exclude-vcs --exclude '*.test' --exclude 'testdata' pkg | \
		tar -C ${D}${libdir}/pvgo --no-same-owner -xf -

	if ls ${B}/${GO_BUILD_BINDIR}/* >/dev/null 2>/dev/null ; then
		install -d ${D}${bindir}
		install -m 0755 ${B}/${GO_BUILD_BINDIR}/* ${D}${bindir}/
	fi
}

pvgo_stage_testdata() {
	oldwd="$PWD"
	cd ${S}/src
	find ${GO_IMPORT} -depth -type d -name testdata | while read d; do
		if echo "$d" | grep -q '/vendor/'; then
			continue
		fi
		parent=`dirname $d`
		install -d ${D}${PTEST_PATH}/$parent
		cp --preserve=mode,timestamps -R $d ${D}${PTEST_PATH}/$parent/
	done
	cd "$oldwd"
}

EXPORT_FUNCTIONS do_unpack do_configure do_compile do_install

FILES:${PN}-dev = "${libdir}/pvgo/src"
FILES:${PN}-staticdev = "${libdir}/pvgo/pkg"

INSANE_SKIP:${PN} += "ldflags"

python() {
    if 'mips' in d.getVar('TARGET_ARCH') or 'riscv32' in d.getVar('TARGET_ARCH'):
        d.appendVar('INSANE_SKIP:%s' % d.getVar('PN'), " textrel")
    else:
        d.appendVar('GOBUILDFLAGS', ' -buildmode=pie')
}
