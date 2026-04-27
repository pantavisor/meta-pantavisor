SUMMARY = "Example agent-app: log triage via the agentic-app skeleton"
DESCRIPTION = "Re-implementation of agentic-log-anomaly using \
agentic-app-skeleton.inc. Demonstrates the contract a product agent-app \
fulfills: ship a system_prompt.md, a tools.json, and a tools.py — the \
skeleton handles the LLM client, feed subscription, JSON-schema validation, \
GBNF grammar generation, and the reasoner loop. Roughly 50 lines of \
product-specific config replaces ~350 lines of hand-rolled Python."

require recipes-containers/agentic/agentic-app-skeleton.inc

IMAGE_BASENAME = "agentic-example-log-triage"

SRC_URI += "file://${BPN}.system_prompt.md \
            file://${BPN}.tools.json \
            file://${BPN}.tools.py \
            file://${BPN}.config.json \
            file://${BPN}.services.json \
            file://${BPN}.args.json"

# Map BPN-prefixed source filenames into the names the skeleton's
# install_agentic_app_files() expects (it uses AGENTIC_APP_NAME, which
# defaults to PN — same value as BPN here).
AGENTIC_APP_NAME = "${BPN}"
