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
FILES:${PN} = "/usr/bin/agentic-app /usr/lib/python3*"

DEPENDS = "python3"
RDEPENDS:${PN} = "python3-core python3-json python3-netserver python3-logging python3-threading"

SRC_URI = "file://agentic_skeleton/__init__.py \
           file://agentic_skeleton/llm.py \
           file://agentic_skeleton/tools.py \
           file://agentic_skeleton/grammar.py \
           file://agentic_skeleton/feed.py \
           file://agentic_skeleton/loop.py \
           file://agentic_skeleton/runtime.py \
           file://agentic-app"

S = "${WORKDIR}"

# The Yocto python3 sysconfig path varies by release. Resolve at do_install
# time using sitelib (matches what python3-core was built against).
do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}/agentic_skeleton
    for f in __init__.py llm.py tools.py grammar.py feed.py loop.py runtime.py; do
        install -m 0644 ${WORKDIR}/agentic_skeleton/$f \
            ${D}${PYTHON_SITEPACKAGES_DIR}/agentic_skeleton/$f
    done
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/agentic-app ${D}${bindir}/agentic-app
}
