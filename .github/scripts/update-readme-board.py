#!/usr/bin/env python3
"""Update the workflow status table in README.md based on .github/workflows/."""

import re
import json
import glob
from pathlib import Path
from urllib.parse import quote

REPO = "pantavisor/meta-pantavisor"
SHIELDS = "https://img.shields.io/github/actions/workflow/status"
GH_ACTIONS = f"https://github.com/{REPO}/actions/workflows"

# Workflows that are internal/reusable and should not appear in the table
EXCLUDE_PREFIXES = ("buildkas-", "call-")

BADGE_STYLE = "flat-square"
BADGE_LOGO = "github-actions"
BADGE_LOGO_COLOR = "white"

# Map filename prefix → short badge label
PREFIX_LABEL = {
    "tag":      "TAG",
    "onpush":   "PUSH",
    "manual":   "MAN",
    "schedule": "SCHEDULE",
    "scheadule": "SCHEDULE",  # typo variant
}


def badge(workflow_file, label):
    encoded_label = quote(label, safe="")
    badge_url = (
        f"{SHIELDS}/{REPO}/{workflow_file}"
        f"?style={BADGE_STYLE}&logo={BADGE_LOGO}&logoColor={BADGE_LOGO_COLOR}&label={encoded_label}"
    )
    workflow_url = f"{GH_ACTIONS}/{workflow_file}"
    return f"[![{label}]({badge_url})]({workflow_url})"


with open(".github/machines.json") as f:
    data = json.load(f)

branch = data["yocto_branch"]

workflows = sorted(
    Path(f).name
    for f in glob.glob(".github/workflows/*.yaml")
    if not any(Path(f).name.startswith(p) for p in EXCLUDE_PREFIXES)
)

rows = ["| Workflow | Status |", "| :--- | :--- |"]
for wf in workflows:
    prefix = wf.split("-")[0]
    label = PREFIX_LABEL.get(prefix, prefix.upper())
    name = wf.replace(".yaml", "")
    rows.append(f"| **{name}** | {badge(wf, label)} |")

table = "\n".join(rows)

with open("README.md") as f:
    content = f.read()

content = re.sub(
    r"<!-- WORKFLOW_TABLE_START -->.*?<!-- WORKFLOW_TABLE_END -->",
    f"<!-- WORKFLOW_TABLE_START -->\n{table}\n<!-- WORKFLOW_TABLE_END -->",
    content,
    flags=re.DOTALL,
)

with open("README.md", "w") as f:
    f.write(content)

print("README.md table updated!")
