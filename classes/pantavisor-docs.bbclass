# Image class that collects documentation from all components in the image and
# packages it alongside the layer's own docs into a single deployable tarball
# and a Sphinx-rendered single-page HTML reference document.
#
# Component recipes must inherit pantacor-component-docs.
# Recipes without DOCS_SRC_DIR or DOCS_FILES are silently excluded.
#
# Outputs:
#   ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst
#   ${DEPLOY_DIR_IMAGE}/pantavisor-reference-documentation-<hash>[+<tag>].html.tar.zst
#   ${DEPLOY_DIR_IMAGE}/pantavisor-reference-documentation.html.tar.zst  (stable symlink)
#
# HTML pipeline:
#   pantavisor-docs-gen-html.py (stdlib only) merges all Markdown sources into
#   a single RST file, following the reading order defined in each index.md,
#   resolving internal links to RST :ref: labels, and prepending a full TOC.
#   sphinx-build (python3-sphinx-native) converts that RST to singlehtml.
#   No Markdown extension is needed — RST is Sphinx's native format.
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
    ${WORKDIR}/sphinx-src \
    ${WORKDIR}/sphinx-html \
    ${DEPLOY_DIR_IMAGE} \
"
do_create_pantacor_docs[cleandirs] = " \
    ${WORKDIR}/pantacor-docs-staging \
    ${WORKDIR}/sphinx-src \
    ${WORKDIR}/sphinx-html \
"
do_create_pantacor_docs[depends] += " \
    zstd-native:do_populate_sysroot \
    python3-sphinx-native:do_populate_sysroot \
    pantavisor:do_create_component_docs \
"
do_create_pantacor_docs[file-checksums] += "${META_PANTAVISOR_BASE}/classes/pantavisor-docs-gen-html.py:True"

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

    # --- RST generation ----------------------------------------------------
    # Python script merges all Markdown into one RST file, following index.md
    # reading order, excluding index files, resolving cross-links.
    python3 "${META_PANTAVISOR_BASE}/classes/pantavisor-docs-gen-html.py" \
        "$staging" "${WORKDIR}/sphinx-src/merged.rst" "$version_str" \
        || bbwarn "${PN}: RST merge step failed"

    # Minimal Sphinx conf.py — RST only, no Markdown extension needed
    cat > "${WORKDIR}/sphinx-src/conf.py" <<'CONFEOF'
project = 'Pantavisor Reference Documentation'
master_doc = 'merged'
html_theme = 'alabaster'
exclude_patterns = ['_build']
CONFEOF

    # --- HTML generation via Sphinx ----------------------------------------
    sphinx-build -b singlehtml \
        "${WORKDIR}/sphinx-src" "${WORKDIR}/sphinx-html" \
        || bbwarn "${PN}: sphinx-build failed"

    html_tar="${DEPLOY_DIR_IMAGE}/pantavisor-reference-documentation-${version_str}.html.tar.zst"
    tar -C "${WORKDIR}/sphinx-html" \
        --use-compress-program=zstd \
        --exclude='.doctrees' \
        -cf "$html_tar" .
    ln -fsr "$html_tar" \
        "${DEPLOY_DIR_IMAGE}/pantavisor-reference-documentation.html.tar.zst"

    # --- Markdown tarball --------------------------------------------------
    outfile="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst"
    tar -C "$staging" --use-compress-program=zstd -cf "$outfile" .
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.docs.tar.zst"
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.${version_str}.docs.tar.zst"
}

addtask do_create_pantacor_docs after do_rootfs_pvroot before do_build
