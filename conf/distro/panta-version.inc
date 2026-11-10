# Shared by every panta distro so they all stamp the same version.
# --tags: RC tags are lightweight (docs/overview/ci/changelog.md, RC flow);
#   without it describe falls back to the last annotated tag.
# --match: numbered release tags only, as onpush-containers.yaml does.
# --always: CI fetches tags at depth 1; an untagged commit has none in reach.
# cwd is the layer, not FILE: FILE is the recipe, which for a poky recipe
#   would describe poky's checkout.
# bb.process.run instead of oe.buildcfg: kirkstone has no buildcfg.py.
DISTRO_VERSION = "${@bb.process.run(['git', 'describe', '--tags', '--match', '[0-9][0-9][0-9]*', '--always', '--dirty'], cwd=d.getVar('META_PANTAVISOR_BASE'))[0].strip()}"

# Without this, signatures hash the expression above rather than its result,
# so a new tag, commit or -dirty never invalidates sstate and the old version
# string ships in pantavisor and /etc/build. Same fix as METADATA_REVISION in
# poky's metadata_scm.bbclass.
DISTRO_VERSION[vardepvalue] = "${DISTRO_VERSION}"
