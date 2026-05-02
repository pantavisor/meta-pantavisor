SUMMARY = "Generic agent-app harness — reasoner loop, tool dispatch, schema validation"
DESCRIPTION = "A reusable Python package + /usr/bin/agentic-app entrypoint \
that turns a product container into an agentic device app by overriding \
just three files: system_prompt.md, tools.json, and tools.py. The skeleton \
handles HTTP-over-UDS to pv-llama, NDJSON xconnect feed subscription, \
JSON-schema validation, GBNF grammar generation for tool-call \
constrained generation, and the reasoner loop."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# This recipe ships ONLY the harness — it is consumed by product agent-app
# recipes (which inherit recipes-containers/agentic/agentic-app-skeleton.inc).
# We don't produce a runnable container image from this recipe alone.
PACKAGES = "${PN}"
FILES:${PN} = "${bindir}/agentic-app ${libdir}/agentic-app ${sysconfdir}/agentic-app"

RDEPENDS:${PN} = "python3-core python3-json python3-netserver python3-logging python3-threading"

SRC_URI = "file://agentic_skeleton/__init__.py \
           file://agentic_skeleton/llm.py \
           file://agentic_skeleton/tools.py \
           file://agentic_skeleton/grammar.py \
           file://agentic_skeleton/feed.py \
           file://agentic_skeleton/loop.py \
           file://agentic_skeleton/runtime.py \
           file://agentic-app \
           file://pv-agentic.runtime.json"

S = "${WORKDIR}"

# Install the package under /usr/lib/agentic-app/agentic_skeleton/ rather
# than into Python's site-packages dir. Yocto's PYTHON_SITEPACKAGES_DIR
# only resolves correctly when one of the python3 bbclasses is inherited
# (setuptools3 / distutils3 / pep517-wheel), and our package has no
# build step worth pulling in those classes for. A fixed path under
# /usr/lib keeps the recipe simple, and /usr/bin/agentic-app prepends it
# to sys.path before importing the package.
SKELETON_LIBDIR = "${libdir}/agentic-app/agentic_skeleton"

do_install() {
    install -d ${D}${SKELETON_LIBDIR}
    for f in __init__.py llm.py tools.py grammar.py feed.py loop.py runtime.py; do
        install -m 0644 ${WORKDIR}/agentic_skeleton/$f \
            ${D}${SKELETON_LIBDIR}/$f
    done
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/agentic-app ${D}${bindir}/agentic-app

    # Ship a known-good default runtime config that every agent-app inherits.
    # Per-app recipes can override individual keys by installing
    # ${PN}.runtime.json (which lands as /etc/agentic-app/config.json); the
    # skeleton runtime deep-merges config.json over defaults.json so apps
    # only declare what they actually change.
    install -d ${D}${sysconfdir}/agentic-app
    install -m 0644 ${WORKDIR}/pv-agentic.runtime.json \
        ${D}${sysconfdir}/agentic-app/defaults.json
}
