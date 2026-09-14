DESCRIPTION = "This is a simple example recipe that cross-compiles a Go program."
SECTION = "pantacor"
HOMEPAGE = "https://golang.org/"

inherit pvgo_mod deploy pantacor-component-docs


# pvr's release src.tar.gz only ever contains go.mod/go.sum/Makefile/*.go
# (see pvr's .gitlab-ci.yml package-deploy job), so docs/ is fetched
# separately via GitLab's repository archive API pinned to the same tag (see
# DOCS_SRC_URI below) and relocated into ${S}/docs by relocate_source,
# matching pantacor-component-docs' default DOCS_SRC_DIR.
DOCS_COMPONENT_NAME = "pvr"
DOCS_SRC_URI = "https://gitlab.com/api/v4/projects/pantacor%2Fpvr/repository/archive.tar.gz?sha=${PV}&path=docs;name=docs;subdir=docs-src;downloadfilename=pvr.${PV}.docs.tar.gz"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

S = "${WORKDIR}"

SRC_URI = " \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.src.tar.gz;name=pvr; \
        https://gitlab.com/api/v4/projects/pantacor%2Fpvr/packages/generic/pvr/${PV}/pvr.${PV}.vendor.tar.gz;name=vendor;subdir=src/${GO_IMPORT} \
"

SRC_URI[pvr.sha256sum] = "5552f8c5b20e4e74728f02754c6d098c9c9442b4c3ebb97e1278fbcaed95e619"
SRC_URI[vendor.sha256sum] = "bec939d53c4f739dbf4b645678728fc1074c10fefe52a4b6d24b7232b1a4d916"
SRC_URI[docs.sha256sum] = "abd293d5bf51fd78b853d533b3167f879fd957137d3cb0063ffd2748850ea6d8"

GO_IMPORT = "gitlab.com/pantacor/pvr"
export GO111MODULE="on"

GOBUILDFLAGS += "-mod=vendor"

# Without this the binary reports 'pvr version: NA' — cmd.Version defaults to
# that and only upstream's Makefile injects it. Revision is deliberately left
# at NA: there is no git checkout here, and the version printer omits it when
# it is unset rather than printing a bogus one.
GO_EXTRA_LDFLAGS += "-X gitlab.com/pantacor/pvr/cmd.Version=${PV}"
GO_LINKSHARED = ""
GO_LINKMODE:class-nativesdk = ""
GO_LINKMODE:class-native = ""


do_unpack[cleandirs] += "${S}/src/${GO_IMPORT}"
relocate_source() {
  cp -fr ${S}/pvr-*/* ${S}/src/${GO_IMPORT}
  if [ -d ${S}/docs-src ]; then
    cp -r ${S}/docs-src/*/docs ${S}/docs
  fi
}
do_patch[postfuncs] += "relocate_source"

# A second, fully static build of the same source. CGO off means the binary
# carries no ELF interpreter, so one artifact runs on glibc and musl hosts
# alike — which the ordinary build does not: the target one wants
# /lib/ld-linux-*.so and the native one an interpreter under ${TMPDIR}.
# The pvtest native runner ships this for the host it runs on.
do_compile:append() {
        export TMPDIR="${GOTMPDIR}"
        cd ${B}/src/${GO_IMPORT}
        CGO_ENABLED=0 ${GO} build -mod=vendor -trimpath \
                -ldflags "-X gitlab.com/pantacor/pvr/cmd.Version=${PV}" \
                -o ${B}/pvr-static .
}

do_install:append() {
        install -d ${D}${bindir}
        install -m 755 ${B}/pvr-static ${D}${bindir}/pvr-static
}

PACKAGES =+ "${PN}-static"
FILES:${PN}-static = "${bindir}/pvr-static"
# Nothing to strip or debug-split: a static Go binary has no section header
INSANE_SKIP:${PN}-static += "already-stripped"

# Stage into DEPLOYDIR so sstate captures the files; a setscene restore of a
# task that wrote to DEPLOY_DIR_TOOLS directly leaves the tools dir empty.
do_deploy[sstate-outputdirs] = "${DEPLOY_DIR_TOOLS}"

do_deploy() {
        install -m 755 ${B}/${GO_BUILD_BINDIR}/pvr ${DEPLOYDIR}/pvr-${PACKAGE_ARCH}
        install -m 755 ${B}/pvr-static ${DEPLOYDIR}/pvr-static-${PACKAGE_ARCH}
}

addtask deploy after do_install

BBCLASSEXTEND = "native nativesdk"
