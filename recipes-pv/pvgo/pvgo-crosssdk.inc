#
# pvgo-crosssdk.inc - SDK Go compiler built with the pvgo toolchain
#
# Mirrors poky's go-crosssdk.inc: it builds a Go command that runs on the
# build host and targets the SDK, which class-nativesdk recipes (e.g. pvr)
# need in order to compile for the SDK host.
#
# SPDX-License-Identifier: MIT
#

inherit crosssdk

# class-nativesdk clients depend on virtual/${TARGET_PREFIX}pvgo, which the
# nativesdk class extender rewrites to virtual/nativesdk-${TARGET_PREFIX}pvgo.
# Unlike poky's virtual/${TARGET_PREFIX}go, the -pvgo suffix does not hit the
# triplet exclusion in extend_name(), so the provider name must carry the
# nativesdk- prefix as well.
PROVIDES = "virtual/nativesdk-${TARGET_PREFIX}pvgo"
DEPENDS = "pvgo-bootstrap-native virtual/${TARGET_PREFIX}gcc virtual/nativesdk-${TARGET_PREFIX}compilerlibs virtual/${TARGET_PREFIX}binutils"
PN = "pvgo-crosssdk-${SDK_SYS}"

export GOCACHE = "${B}/.cache"

do_configure[noexec] = "1"

do_compile() {
	export CC_FOR_${TARGET_GOTUPLE}="${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} --sysroot=${STAGING_DIR_TARGET}"
	export CXX_FOR_${TARGET_GOTUPLE}="${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} --sysroot=${STAGING_DIR_TARGET}"
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
export GOROOT=\`readlink -f \$here/../../lib/${CROSS_TARGET_SYS_DIR}/pvgo\`
export GOARCH="${TARGET_GOARCH}"
export GOOS="${TARGET_GOOS}"
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
