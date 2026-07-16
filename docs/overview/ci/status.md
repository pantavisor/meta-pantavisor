---
sidebar_position: 4
---
# CI Status

## Workflow Status

<!-- WORKFLOW_TABLE_START -->
| Workflow | Status |
| :--- | :--- |
| **manual-pvtests** | [![MAN](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/manual-pvtests.yaml?style=flat-square&logo=github-actions&logoColor=white&label=MAN)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/manual-pvtests.yaml) |
| **manual-scarthgap** | [![MAN](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/manual-scarthgap.yaml?style=flat-square&logo=github-actions&logoColor=white&label=MAN)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/manual-scarthgap.yaml) |
| **onpush-scarthgap** | [![PUSH](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/onpush-scarthgap.yaml?style=flat-square&logo=github-actions&logoColor=white&label=PUSH)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/onpush-scarthgap.yaml) |
| **schedule-pvtests** | [![SCHEDULE](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/schedule-pvtests.yaml?style=flat-square&logo=github-actions&logoColor=white&label=SCHEDULE)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-pvtests.yaml) |
| **schedule-updatemachines** | [![SCHEDULE](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/schedule-updatemachines.yaml?style=flat-square&logo=github-actions&logoColor=white&label=SCHEDULE)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-updatemachines.yaml) |
| **schedule-updates** | [![SCHEDULE](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/schedule-updates.yaml?style=flat-square&logo=github-actions&logoColor=white&label=SCHEDULE)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/schedule-updates.yaml) |
| **tag-changelogs** | [![TAG](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/tag-changelogs.yaml?style=flat-square&logo=github-actions&logoColor=white&label=TAG)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-changelogs.yaml) |
| **tag-docs-scarthgap** | [![TAG](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/tag-docs-scarthgap.yaml?style=flat-square&logo=github-actions&logoColor=white&label=TAG)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-docs-scarthgap.yaml) |
| **tag-scarthgap** | [![TAG](https://img.shields.io/github/actions/workflow/status/pantavisor/meta-pantavisor/tag-scarthgap.yaml?style=flat-square&logo=github-actions&logoColor=white&label=TAG)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- WORKFLOW_TABLE_END -->

## Latest Release Build

Per-machine badge data is uploaded to S3 by `upload-badges` at the end of each tag build. Badges reflect the result of the most recent stable or release-candidate run. See [builds.md](builds.md) for how they are generated.

### Stable [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_STABLE_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8mn-var-som-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| verdin-imx8mm-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/verdin-imx8mm-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| colibri-imx6ull-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/stable/badges/colibri-imx6ull-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_STABLE_END -->

### Release Candidate [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/tag.json)](https://github.com/pantavisor/meta-pantavisor/releases)

<!-- BUILD_SUMMARY_RC_START -->
| Machine | Status |
| :--- | :--- |
| radxa-rock5a-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/radxa-rock5a-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-bananapi-m2-berry-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-bananapi-m2-berry-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8qxp-b0-mek-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8qxp-b0-mek-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-3lts-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-orange-pi-3lts-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| raspberrypi-armv8-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/raspberrypi-armv8-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mn-var-som-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8mn-var-som-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| imx8mm-var-dart-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/imx8mm-var-dart-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| sunxi-orange-pi-r1-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/sunxi-orange-pi-r1-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| rpi-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/rpi-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| docker-x86_64-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/docker-x86_64-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| verdin-imx8mm-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/verdin-imx8mm-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
| colibri-imx6ull-scarthgap | [![](https://img.shields.io/endpoint?url=https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/latest/release-candidate/badges/colibri-imx6ull-scarthgap.json)](https://github.com/pantavisor/meta-pantavisor/actions/workflows/tag-scarthgap.yaml) |
<!-- BUILD_SUMMARY_RC_END -->
