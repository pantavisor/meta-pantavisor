SUMMARY = "pvtx web UI for the pvr SDK"
DESCRIPTION = "React app served from /www/app by the SDK's httpd; talks to the pvtx CGI API."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${WORKDIR}/git/LICENSE;md5=70175346ce0d7913626f30a67d153851"

# Same commit as pv-pvr-sdk (v1.3.3); PV follows pvtx-app/package.json.
SRCREV = "b858cb6936ab3ec653cbd54332fc1daa62f599a3"
SRC_URI = "git://gitlab.com/pantacor/pv-platforms/pvr-sdk;protocol=https;branch=master"
S = "${WORKDIR}/git/pvtx-app"

DEPENDS = "nodejs-native"

inherit allarch

# yarn resolves the dependency tree from yarn.lock against the npm registry, so
# this is the one task in the layer that needs network access. The lockfile
# pins every version and hash, so the result is still reproducible; it just
# cannot build from a pre-populated DL_DIR/offline mirror.
do_compile[network] = "1"

do_compile() {
    export HOME=${WORKDIR}/home
    export npm_config_cache=${WORKDIR}/npm-cache
    mkdir -p ${HOME}

    # No yarn recipe exists; the lockfile is yarn v1 format.
    npm install --no-save --prefix ${WORKDIR}/tools yarn@1.22.22
    export PATH=${WORKDIR}/tools/node_modules/.bin:$PATH

    yarn install --frozen-lockfile
    yarn build
}

do_install() {
    install -d ${D}/www
    cp -r ${S}/app ${D}/www/app
}

FILES:${PN} = "/www/app"
