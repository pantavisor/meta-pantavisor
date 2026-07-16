DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantacor"
HOMEPAGE = "https://golang.org/"

inherit pvgo_mod deploy pantacor-component-docs


# TODO: docs moved from the root README.md to a docs/ folder (pvr commit
# fd286b27, "docs: add full command reference and simplify README"), but that
# commit isn't in any tagged release yet (latest tag is 051; this recipe
# pins 050). Neither a raw-URL fetch nor the release src tarball can reach
# docs/ until pvr cuts a release that includes it. Re-wire DOCS_FILES/
# DOCS_SRC_DIR to pull from docs/ once this recipe is bumped to such a tag.
DOCS_COMPONENT_NAME = "pvr"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

SRC_URI = " \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.src.tar.gz;name=pvr; \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[pvr.sha256sum] = "9cba05717f2fd6e8d8fa2bd8aaef0e4b641f7ef81afebbf498c50eaf4bc83bf5"
SRC_URI[vendor.sha256sum] = "019feba257ee70b0d10775cc1a8547e113f8adc07c66898e041d09f8a6413e6d"

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
