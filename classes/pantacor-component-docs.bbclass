# Packages a component's documentation for collection by the pantavisor-docs image class.
#
# Set in your recipe:
#   DOCS_SRC_DIR        — directory to archive recursively (default: ${S}/docs)
#   DOCS_FILES          — space-separated list of specific files to include instead of
#                         a whole directory; takes precedence over DOCS_SRC_DIR
#   DOCS_COMPONENT_NAME — directory name in the combined image tarball (default: ${BPN})
#   DOCS_SRC_URI        — optional extra SRC_URI entry (fetcher URL + params) needed only to
#                         obtain the docs, e.g. when a recipe's normal source fetch doesn't
#                         include docs/. Appended to SRC_URI, but dropped for class-native/
#                         class-nativesdk since do_create_component_docs doesn't run there.
#
# Recipes that have neither a valid DOCS_SRC_DIR nor DOCS_FILES are skipped with a warning.

DOCS_SRC_DIR ?= "${S}/docs"
DOCS_FILES ?= ""
DOCS_COMPONENT_NAME ?= "${BPN}"
DOCS_SRC_URI ?= ""

SRC_URI:append = " ${DOCS_SRC_URI}"
SRC_URI:remove:class-native = "${DOCS_SRC_URI}"
SRC_URI:remove:class-nativesdk = "${DOCS_SRC_URI}"

SSTATETASKS += "do_create_component_docs"

python __anonymous() {
    classoverride = d.getVar('CLASSOVERRIDE') or ''
    if classoverride in ('class-native', 'class-nativesdk'):
        bb.build.deltask('do_create_component_docs', d)
        bb.build.deltask('do_create_component_docs_setscene', d)
        sstatetasks = (d.getVar('SSTATETASKS') or '').split()
        if 'do_create_component_docs' in sstatetasks:
            sstatetasks.remove('do_create_component_docs')
            d.setVar('SSTATETASKS', ' '.join(sstatetasks))
}

do_create_component_docs[dirs] = "${WORKDIR}/pantacor-docs-staging ${WORKDIR}/pantacor-docs-deploy"
do_create_component_docs[cleandirs] = "${WORKDIR}/pantacor-docs-staging ${WORKDIR}/pantacor-docs-deploy"
do_create_component_docs[depends] += "zstd-native:do_populate_sysroot"
do_create_component_docs[stamp-extra-info] = "${MACHINE_ARCH}"
do_create_component_docs[sstate-inputdirs] = "${WORKDIR}/pantacor-docs-deploy"
do_create_component_docs[sstate-outputdirs] = "${DEPLOY_DIR_IMAGE}"

python do_create_component_docs_setscene () {
    sstate_setscene(d)
}

do_create_component_docs() {
    staging="${WORKDIR}/pantacor-docs-staging/${DOCS_COMPONENT_NAME}"
    install -d "$staging"

    if [ -n "${DOCS_FILES}" ]; then
        for f in ${DOCS_FILES}; do
            if [ -f "$f" ]; then
                install -m 0644 "$f" "$staging/"
            else
                bbwarn "${PN}: docs file '$f' not found, skipping"
            fi
        done
    elif [ -d "${DOCS_SRC_DIR}" ]; then
        cp -r "${DOCS_SRC_DIR}/." "$staging/"
    else
        bbwarn "${PN}: DOCS_SRC_DIR '${DOCS_SRC_DIR}' does not exist and DOCS_FILES is unset, skipping"
        return 0
    fi

    if [ -z "$(find "$staging" -mindepth 1 -print -quit)" ]; then
        bbwarn "${PN}: no documentation content found, skipping"
        return 0
    fi

    tar -C "${WORKDIR}/pantacor-docs-staging" \
        --use-compress-program=zstd \
        -cf "${WORKDIR}/pantacor-docs-deploy/${BPN}-component-docs.tar.zst" \
        "${DOCS_COMPONENT_NAME}"
}

addtask do_create_component_docs after do_install before do_deploy do_build
