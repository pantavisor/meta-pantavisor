# Image class that collects documentation from all components in the image and
# packages it alongside the layer's own docs into a single deployable tarball
# and a Sphinx-rendered single-page HTML reference document.
#
# Component recipes must inherit pantacor-component-docs.
# Recipes without DOCS_SRC_DIR or DOCS_FILES are silently excluded.
#
# Outputs:
#   ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst
#
# Tarball layout:
#   index.md           ← root index linking both document sets
#   meta-pantavisor/   ← ${LAYERDIR}/docs
#   <bpn>/             ← per-component docs (one dir per component)
#
# Variables:
#   PANTACOR_LAYER_DOCS        — layer docs source (default: ${META_PANTAVISOR_BASE}/docs)
#   PANTACOR_LAYER_DOCS_NAME   — top-level dir name in the tarball (default: meta-pantavisor)

PANTACOR_LAYER_DOCS ?= "${META_PANTAVISOR_BASE}/docs"
PANTACOR_LAYER_DOCS_NAME ?= "meta-pantavisor"

do_create_pantacor_docs[dirs] = " \
    ${WORKDIR}/pantacor-docs-staging \
    ${DEPLOY_DIR_IMAGE} \
"
do_create_pantacor_docs[cleandirs] = " \
    ${WORKDIR}/pantacor-docs-staging \
"
do_create_pantacor_docs[depends] += " \
    zstd-native:do_populate_sysroot \
    pantavisor:do_create_component_docs \
    pvr:do_create_component_docs \
"

do_create_pantacor_docs() {
    staging="${WORKDIR}/pantacor-docs-staging"

    # Layer docs → meta-pantavisor/
    if [ -d "${PANTACOR_LAYER_DOCS}" ]; then
        install -d "${staging}/${PANTACOR_LAYER_DOCS_NAME}"
        cp -r "${PANTACOR_LAYER_DOCS}/." "${staging}/${PANTACOR_LAYER_DOCS_NAME}/"
    else
        bbwarn "${PN}: PANTACOR_LAYER_DOCS '${PANTACOR_LAYER_DOCS}' not found, skipping layer docs"
    fi

    # Component docs tarballs → one subdir per component
    for doctar in "${DEPLOY_DIR_IMAGE}"/*-component-docs.tar.zst; do
        [ -f "$doctar" ] || continue
        tar -C "$staging" --use-compress-program=zstd -xf "$doctar"
    done

    # Root index — only list sections that are actually present in staging
    {
        printf '# Pantavisor Documentation\n\n'
        printf 'This archive bundles reference documentation shipped alongside the build artefacts.\n\n'
        [ -d "${staging}/pantavisor" ] && \
            printf -- '- **[Pantavisor](pantavisor/)** — the embedded Linux runtime that manages\n  the device lifecycle: booting containers, applying atomic OTA updates, and\n  exposing a REST API for local and cloud control.\n\n'
        [ -d "${staging}/pvr" ] && \
            printf -- '- **[PVR](pvr/)** — the Pantavisor command-line utility for creating,\n  managing, and deploying containerized applications to Pantavisor devices.\n\n'
        [ -d "${staging}/meta-pantavisor" ] && \
            printf -- '- **[meta-pantavisor](meta-pantavisor/)** — the Yocto/OpenEmbedded layer\n  used to build Pantavisor-based BSP images. Covers the build system, KAS\n  configurations, BitBake recipes, and the CI/release pipeline.\n\n'
        [ -d "${staging}/meta-pantavisor" ] && \
            printf 'Start with [meta-pantavisor/index.md](meta-pantavisor/index.md) for a guided\nreading order, or jump straight into either section above.\n'
    } > "${staging}/index.md"

    # Version string shared by the HTML tarball name and the markdown tarball symlink
    git_hash=$(git -C "${META_PANTAVISOR_BASE}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    git_tag=$(git -C "${META_PANTAVISOR_BASE}" describe --exact-match HEAD 2>/dev/null || true)
    if [ -n "$git_tag" ]; then
        version_str="${git_hash}+${git_tag}"
    else
        version_str="${git_hash}"
    fi


    # --- Markdown tarball --------------------------------------------------
    outfile="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst"
    tar -C "$staging" --use-compress-program=zstd -cf "$outfile" .
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.docs.tar.zst"
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.${version_str}.docs.tar.zst"
}

addtask do_create_pantacor_docs after do_rootfs_pvroot before do_build
