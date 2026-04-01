DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantacor"
HOMEPAGE = "https://golang.org/"

inherit pvgo_mod deploy

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

SRC_URI = " \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.src.tar.gz;name=pvr; \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[pvr.sha256sum] = "5177d08547000f23763874991fd3881eebc3d6a491d5a627da08b6cb34175e22"
SRC_URI[vendor.sha256sum] = "ad7795e2d5431e459b01031b588f7e84a61c770865203a09bc5a35f6593bdbec"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

GOBUILDFLAGS += "-mod=vendor"
GO_LINKSHARED = ""
GO_LINKMODE:class-nativesdk = ""
GO_LINKMODE:class-native = ""


do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
  cp -fr ${S}/pvr-*/* ${S}/src/${GO_IMPORT}
}
do_patch[postfuncs] += "relocate_source"

do_deploy[sstate-outputdirs] = "${DEPLOY_DIR_TOOLS}"
do_deploy[dirs] += "${DEPLOY_DIR_TOOLS}"

do_deploy() {
        install -m 755 ${B}/${GO_BUILD_BINDIR}/pvr ${DEPLOY_DIR_TOOLS}/pvr-${PACKAGE_ARCH}
}

addtask deploy after do_install

BBCLASSEXTEND = "native nativesdk"
