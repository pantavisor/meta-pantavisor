# Packages a component's documentation for collection by the pantavisor-docs image class.
#
# Set in your recipe:
#   DOCS_SRC_DIR        — directory to archive recursively (default: ${S}/docs)
#   DOCS_FILES          — space-separated list of specific files to include instead of
#                         a whole directory; takes precedence over DOCS_SRC_DIR
#   DOCS_COMPONENT_NAME — directory name in the combined image tarball (default: ${BPN})
#
# Recipes that have neither a valid DOCS_SRC_DIR nor DOCS_FILES are skipped with a warning.

DOCS_SRC_DIR ?= "${S}/docs"
DOCS_FILES ?= ""
DOCS_COMPONENT_NAME ?= "${BPN}"

do_create_component_docs[dirs] = "${WORKDIR}/pantacor-docs-staging ${DEPLOY_DIR_IMAGE}"
do_create_component_docs[cleandirs] = "${WORKDIR}/pantacor-docs-staging"
do_create_component_docs[depends] += "zstd-native:do_populate_sysroot"
do_create_component_docs[stamp-extra-info] = "${MACHINE_ARCH}"

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

    tar -C "${WORKDIR}/pantacor-docs-staging" \
        --use-compress-program=zstd \
        -cf "${DEPLOY_DIR_IMAGE}/${BPN}-component-docs.tar.zst" \
        "${DOCS_COMPONENT_NAME}"
}

addtask do_create_component_docs after do_install before do_build
