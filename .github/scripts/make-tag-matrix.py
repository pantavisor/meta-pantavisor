#!/usr/bin/env python3
"""Generate the tag matrix workflow from machines.json."""

import json

with open(".github/machines.json") as f:
    data = json.load(f)

branch = data["yocto_branch"]
machines = [m for m in data["machines"] if "tag" in m.get("workflows", [])]
outfile = f".github/workflows/tag-{branch}.yaml"

SUMMARY_JOB = [
    "",
    "  summary:",
    "    needs: build",
    "    if: always()",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - name: Build Summary",
    "        env:",
    "          GH_TOKEN: ${{ github.token }}",
    "        run: |",
    '          echo "## Build Summary" >> $GITHUB_STEP_SUMMARY',
    '          echo "" >> $GITHUB_STEP_SUMMARY',
    '          echo "| Machine | Result |" >> $GITHUB_STEP_SUMMARY',
    '          echo "| :--- | :--- |" >> $GITHUB_STEP_SUMMARY',
    """          gh api repos/${{ github.repository }}/actions/runs/${{ github.run_id }}/jobs | jq -r '.jobs[] | select(.name | startswith("build (")) | "| " + (.name | ltrimstr("build (") | rtrimstr(")")) + " | " + (if .conclusion == "success" then "✅" elif .conclusion == "failure" then "❌" elif .conclusion == "cancelled" then "🚫" elif .conclusion == "skipped" then "⏭️" else (.conclusion // "🔄") end) + " |"' >> $GITHUB_STEP_SUMMARY""",
]

lines = [
    f'name: "TAG: {branch}"',
    "",
    "on:",
    "  push:",
    "    paths:",
    "      - '**'",
    "      - 'kas/build-configs/**'",
    f"      - '.github/workflows/tag-{branch}.yaml'",
    "      - '!.github/scripts/**'",
    "      - '!.github/templates/**'",
    "    tags:",
    "      - 0*",
    "      - '*-rc*'",
    "",
    "jobs:",
    "  build:",
    '    name: "build (${{ matrix.machine_name }})"',
    "    strategy:",
    "      fail-fast: false",
    "      matrix:",
    "        include:",
]

for m in machines:
    name = m["name"]
    build_target = m.get("build_target", "pantavisor-starter")
    output = m.get("output", "pantavisor-starter*.rootfs.wic*").strip()
    sdk = 1 if m.get("sdk") == 1 else 0
    lines += [
        f"          - machine_name: {name}-{branch}",
        f"            configs: kas/build-configs/release/{name}-{branch}.yaml:kas/build-configs/shared-vols.yaml",
        f"            build_target: {build_target}",
        f'            output: "{output}"',
        f"            sdk: {sdk}",
    ]

lines += [
    "    uses: ./.github/workflows/buildkas-upload.yaml",
    "    with:",
    "      configs: ${{ matrix.configs }}",
    "      machine_name: ${{ matrix.machine_name }}",
    "      build_target: ${{ matrix.build_target }}",
    "      output: ${{ matrix.output }}",
    "      sdk: ${{ matrix.sdk }}",
    "    secrets: inherit",
]

lines += SUMMARY_JOB

with open(outfile, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"new tag matrix workflow: {outfile}")
