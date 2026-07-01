---
sidebar_position: 2
---
# Machine Configuration

All CI behavior is controlled by `.github/machines.json`. Adding, removing, or reconfiguring a machine means editing this file and regenerating the workflows — no manual YAML editing required.

## machines.json Schema

```json
{
  "yocto_branch": "scarthgap",
  "machines": [
    {
      "name":         "raspberrypi-armv8",
      "config":       "kas/machines/raspberrypi-armv8.yaml:kas/scarthgap.yaml:...",
      "workflows":    ["manual", "tag", "onpush"],
      "build_target": "pantavisor-starter",
      "output":       "pantavisor-starter*.rootfs.wic*",
      "sdk":          1
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `yocto_branch` | yes | Yocto release name; used as a suffix in all generated file names |
| `name` | yes | Machine identifier; combined with `yocto_branch` in workflow jobs |
| `config` | yes | Colon-separated KAS config fragments to compose for this machine |
| `workflows` | yes | Which workflow types to generate: `manual`, `onpush`, `tag` |
| `build_target` | no | BitBake target (default: `pantavisor-starter`) |
| `output` | no | Glob for artifacts to collect (default: `pantavisor-starter*.rootfs.wic*`) |
| `sdk` | no | Set to `1` to also run `bitbake -c populate_sdk` |

## Workflow Types

| Type | File generated | Trigger | Build engine |
|---|---|---|---|
| `tag` | `release.yaml` | tag push via `tag-scarthgap.yaml` | `buildkas-upload.yaml` (build + S3) |
| `onpush` | `onpush-scarthgap.yaml` | push to master | `buildkas-target.yaml` (build only) |
| `manual` | `manual-scarthgap.yaml` | `workflow_dispatch` | `buildkas-target.yaml` (build only) |

Machines with only `["manual"]` are never built automatically. `colibri-imx6ull` is an example — its NAND flash workflow hasn't been integrated into automated release pipelines.

## Regenerating Workflows

After any change to `machines.json`:

```bash
.github/scripts/makemachines   # flatten KAS fragments → kas/build-configs/release/
.github/scripts/makeworkflows  # regenerate onpush-*, manual-*, release.yaml
```

Always commit `machines.json` together with the generated files.

> `tag-scarthgap.yaml` is **not** regenerated — it is a static orchestrator. Edit it directly when the tag trigger logic needs to change.

## Adding a Machine

1. Add an entry to `.github/machines.json` with `name`, `config`, `workflows`, and any optional fields.
2. Add the KAS machine fragment at `kas/machines/<name>.yaml` if it does not exist.
3. Run `makemachines && makeworkflows`.
4. Verify the generated `kas/build-configs/release/<name>-scarthgap.yaml` looks correct.
5. Commit all four pieces: `machines.json`, the KAS fragment, the release config, and the updated workflow files.

## KAS Config Composition

The `config` field is a colon-separated list of KAS YAML fragments that `kas build` merges in order:

```
kas/machines/<board>.yaml          # board-specific BSP layers and MACHINE
kas/scarthgap.yaml                 # Yocto release pins
kas/bsp-base.yaml                  # common BSP distro settings
kas/build-configs/build-base-starter.yaml  # image target and features
```

Some machines add extra fragments:
- `kas/scarthgap-nxp.yaml` — NXP proprietary layer pins
- `kas/scarthgap-var.yaml` — Variscite BSP pins
- `kas/with-lxc-next.yaml` — LXC 6.x instead of LXC 3.x
- `kas/build-configs/build-base-toradex-starter.yaml` — Toradex-specific targets (see below)
- `kas/build-configs/build-base-uuu-starter.yaml` — Variscite/NXP-MEK UUU targets (see below)

`makemachines` resolves each fragment's `SRCREV` pins and writes a single self-contained `kas/build-configs/release/<name>-scarthgap.yaml` that can reproduce the build without network access to layer repos.

## UUU Factory-Flash Machines (Toradex, Variscite, NXP MEK)

These machines build `pv-flash-bundle`, a self-contained UUU factory-flash
archive, instead of shipping a bare `.wic`. See
[pv-flash-bundle](../overview/pv-flash-bundle.md) for how the recipe itself
works.

`verdin-imx8mm` and `colibri-imx6ull` replace `build-base-starter.yaml` with
`build-base-toradex-starter.yaml`, which specifies three build targets — a
recovery U-Boot is needed because meta-pantavisor's `pv.distroboot.cfg`
overrides the production bootcmd:

```yaml
target:
  - pantavisor-starter
  - mc:tezi-recovery:u-boot-toradex
  - pv-flash-bundle
```

The `tezi-recovery` multiconfig (`DISTRO = "tezi"`) builds the recovery U-Boot
used to enter fastboot mode during UUU flashing. Its output lands in
`tmp-scarthgap-tezi-recovery/` and is picked up by `pv-flash-bundle`.

`imx8mm-var-dart`, `imx8mn-var-som`, and `imx8qxp-b0-mek` replace
`build-base-starter.yaml` with `build-base-uuu-starter.yaml` instead — just
two targets, no recovery multiconfig, since these boards' production
bootloaders already self-enter SDP/fastboot download mode:

```yaml
target:
  - pantavisor-starter
  - pv-flash-bundle
```

All five machines set `"build_target": ""` (so `kas build` runs with no
`--target` override and builds every target in the config's `target:` list)
and `"output"` to just the bundle's own glob, e.g.:

```json
"output": "pv-flash-bundle-colibri-imx6ull.tar.gz"
```

The plain `.wic` is not archived or uploaded to S3 separately for these
machines — it's already inside the bundle (as `.wic.gz`), so a standalone
copy would be redundant. The "Archive pv-flash-bundle artifacts" step in
`buildkas-upload.yaml` picks up whatever `output` copied into `images/`
before uploading; it isn't an independent capture, it depends on `output`
including the bundle's glob.

See [docs/ci/builds.md — UUU Factory-Flash Builds](builds.md#uuu-factory-flash-builds-toradex-variscite-nxp-mek),
[docs/how-to-install/toradex.md](../how-to-install/toradex.md), and
[docs/how-to-install/uuu.md](../how-to-install/uuu.md) for the flash bundle
contents and flashing procedures.

## Automated Machine Updates

`schedule-updatemachines.yaml` runs every 8 hours (offset by 15 minutes from `schedule-updates.yaml`) and executes `makemachines && makeworkflows` inside the KAS container. If the output differs from HEAD, it opens a PR on `autopr/machine-update-master-next`.
