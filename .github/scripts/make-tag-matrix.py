#!/usr/bin/env python3
"""Generate the release workflow from machines.json."""

import json

with open(".github/machines.json") as f:
    data = json.load(f)

branch = data["yocto_branch"]
machines = [m for m in data["machines"] if "tag" in m.get("workflows", [])]
release_outfile = ".github/workflows/release.yaml"

PVTEST_JOBS = [
    "",
    "  pvtest-local:",
    "    needs: build",
    "    uses: ./.github/workflows/call-pvtests.yaml",
    "    with:",
    "      test_path: local",
    "    secrets: inherit",
    "",
    "  pvtest-remote:",
    "    needs: [build, pvtest-local]",
    "    if: always()",
    "    uses: ./.github/workflows/call-pvtests.yaml",
    "    with:",
    "      test_path: remote",
    "    secrets: inherit",
]

SUMMARY_JOB = [
    "",
    "  summary:",
    "    needs: build",
    "    if: always()",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - name: Checkout",
    "        uses: actions/checkout@v6",
    "        with:",
    "          ref: ${{ github.ref }}",
    "      - name: Build Summary",
    "        env:",
    "          GH_TOKEN: ${{ github.token }}",
    "        run: |",
    '          echo "## Build Summary" >> $GITHUB_STEP_SUMMARY',
    '          echo "" >> $GITHUB_STEP_SUMMARY',
    '          echo "| Machine | Result |" >> $GITHUB_STEP_SUMMARY',
    '          echo "| :--- | :--- |" >> $GITHUB_STEP_SUMMARY',
    """          gh api repos/${{ github.repository }}/actions/runs/${{ github.run_id }}/jobs | jq -r '.jobs[] | select(.name | contains("build (")) | "| " + (.name | capture("build \\\\((?<m>[^)]+)\\\\)").m) + " | " + (if .conclusion == "success" then "✅" elif .conclusion == "failure" then "❌" elif .conclusion == "cancelled" then "🚫" elif .conclusion == "skipped" then "⏭️" else (.conclusion // "🔄") end) + " |"' >> $GITHUB_STEP_SUMMARY""",
    "      - name: Upload badges to S3",
    "        env:",
    "          GH_TOKEN: ${{ github.token }}",
    "          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}",
    "          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}",
    "        run: |",
    "          .github/scripts/upload-badges \\",
    "            ${{ github.repository }} \\",
    "            ${{ github.run_id }} \\",
    "            ${{ github.ref_name }} \\",
    "            ${{ secrets.AWS_S3_BUCKET }}",
]

# Generate release.yaml: build matrix + pvtests + summary, called via workflow_call
release_lines = [
    f'name: "ontag: make release, build all targets"',
    "",
    "on:",
    "  workflow_call:",
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
    release_lines += [
        f"          - machine_name: {name}-{branch}",
        f"            configs: kas/build-configs/release/{name}-{branch}.yaml:kas/build-configs/shared-vols.yaml",
        f"            build_target: {build_target}",
        f'            output: "{output}"',
        f"            sdk: {sdk}",
    ]

release_lines += [
    "    uses: ./.github/workflows/buildkas-upload.yaml",
    "    with:",
    "      configs: ${{ matrix.configs }}",
    "      machine_name: ${{ matrix.machine_name }}",
    "      build_target: ${{ matrix.build_target }}",
    "      output: ${{ matrix.output }}",
    "      sdk: ${{ matrix.sdk }}",
    "    secrets: inherit",
]

release_lines += PVTEST_JOBS
release_lines += SUMMARY_JOB

with open(release_outfile, "w") as f:
    f.write("\n".join(release_lines) + "\n")

print(f"new release workflow: {release_outfile}")
