#!/usr/bin/env python3
"""Generate the manual dispatch workflow with a machine choice input from machines.json."""

import json

with open(".github/machines.json") as f:
    data = json.load(f)

branch = data["yocto_branch"]
machines = [m for m in data["machines"] if "manual" in m.get("workflows", [])]
outfile = f".github/workflows/manual-{branch}.yaml"

machine_names = [m["name"] for m in machines]
options = "\n".join(f"          - {name}" for name in machine_names)

content = f"""\
name: "manual: {branch}"

on:
  workflow_dispatch:
    inputs:
      machine:
        description: 'Machine to build'
        required: true
        type: choice
        options:
{options}

jobs:
  resolve:
    runs-on: ubuntu-latest
    outputs:
      configs: ${{{{ steps.lookup.outputs.configs }}}}
      build_target: ${{{{ steps.lookup.outputs.build_target }}}}
      output: ${{{{ steps.lookup.outputs.output }}}}
      sdk: ${{{{ steps.lookup.outputs.sdk }}}}
    steps:
      - uses: actions/checkout@v6
      - id: lookup
        run: |
          machine="${{{{ inputs.machine }}}}"
          build_target=$(jq -r ".machines[] | select(.name == \\"$machine\\") | .build_target // \\"pantavisor-starter\\"" .github/machines.json)
          output=$(jq -r ".machines[] | select(.name == \\"$machine\\") | .output // \\"pantavisor-starter*.rootfs.wic*\\"" .github/machines.json)
          sdk=$(jq -r ".machines[] | select(.name == \\"$machine\\") | if .sdk == 1 then 1 else 0 end" .github/machines.json)
          echo "configs=kas/build-configs/release/$machine-{branch}.yaml:kas/build-configs/shared-vols.yaml" >> $GITHUB_OUTPUT
          echo "build_target=$build_target" >> $GITHUB_OUTPUT
          echo "output=$output" >> $GITHUB_OUTPUT
          echo "sdk=$sdk" >> $GITHUB_OUTPUT

  build:
    needs: resolve
    uses: ./.github/workflows/buildkas-target.yaml
    with:
      configs: ${{{{ needs.resolve.outputs.configs }}}}
      machine_name: ${{{{ inputs.machine }}}}-{branch}
      build_target: ${{{{ needs.resolve.outputs.build_target }}}}
      output: ${{{{ needs.resolve.outputs.output }}}}
      sdk: ${{{{ fromJSON(needs.resolve.outputs.sdk) }}}}
    secrets: inherit
"""

with open(outfile, "w") as f:
    f.write(content)

print(f"new manual dispatch workflow: {outfile}")
