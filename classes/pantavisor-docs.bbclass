# Image class that collects documentation from all components in the image and
# packages it alongside the layer's own docs into a single deployable tarball.
#
# Component recipes must inherit pantacor-component-docs and set DOCS_SRC_DIR.
# Recipes without DOCS_SRC_DIR are silently excluded.
#
# Output: ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst
#
# Tarball layout:
#   meta-pantavisor/   ← ${LAYERDIR}/docs
#   <bpn>/             ← per-component docs (one dir per component)
#
# Variables:
#   PANTACOR_LAYER_DOCS      — layer docs source (default: ${LAYERDIR}/docs)
#   PANTACOR_LAYER_DOCS_NAME — top-level dir name in the tarball (default: meta-pantavisor)

PANTACOR_LAYER_DOCS ?= "${META_PANTAVISOR_BASE}/docs"
PANTACOR_LAYER_DOCS_NAME ?= "meta-pantavisor"

do_create_pantacor_docs[dirs] = "${WORKDIR}/pantacor-docs-staging"
do_create_pantacor_docs[cleandirs] = "${WORKDIR}/pantacor-docs-staging"
do_create_pantacor_docs[depends] += "zstd-native:do_populate_sysroot"
do_create_pantacor_docs[recrdeptask] += "do_create_component_docs"

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

    outfile="${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.rootfs.docs.tar.zst"
    tar -C "$staging" --use-compress-program=zstd -cf "$outfile" .
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.docs.tar.zst"

    # Versioned symlink: <image>.rootfs.<hash>[+<tag>].docs.tar.zst
    git_hash=$(git -C "${META_PANTAVISOR_BASE}" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    git_tag=$(git -C "${META_PANTAVISOR_BASE}" describe --exact-match HEAD 2>/dev/null || true)
    if [ -n "$git_tag" ]; then
        version_str="${git_hash}+${git_tag}"
    else
        version_str="${git_hash}"
    fi
    ln -fsr "$outfile" "${DEPLOY_DIR_IMAGE}/${IMAGE_LINK_NAME}.${version_str}.docs.tar.zst"
}

addtask do_create_pantacor_docs before do_build
