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
      "display_name": "Raspberry Pi 3 / 4 (64-bit)",
      "description":  "64-bit ARMv8 build for the Raspberry Pi 3 and 4. Ships an SDK.",
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
| `display_name` | no | Human-readable board name for the [downloads list](../supported-device.md#downloading-images); copied into `releases.json` by `upload.sh` (falls back to the suffixed machine slug) |
| `description` | no | One- to three-sentence board blurb for the downloads list; copied into `releases.json` by `upload.sh` when non-empty |
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

Machines with only `["manual"]` are never built automatically. `colibri-imx6ull` is an example — its NAND flash workflow hasn't been integrated into automated release pipelines. `raspberrypi-armv8` is another: its ARMv8 coverage on `onpush` is provided by `radxa-rock5a` instead.

## Regenerating Workflows

After any change to `machines.json`:

```bash
.github/scripts/makemachines   # flatten KAS fragments → kas/build-configs/release/
.github/scripts/makeworkflows  # regenerate onpush-*, manual-*, release.yaml
```

Always commit `machines.json` together with the generated files.

When running this from Codex or another restricted development sandbox, run
`makemachines` outside the sandbox with explicit approval. `kas dump
--resolve-refs` performs git repository setup while generating the release
configs and can hang if `.git` metadata is mounted read-only. The scheduled
machine update workflow is unaffected because it runs inside the KAS container.

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

Every machine's chain ends in `build-base-starter.yaml`; a machine that needs
more than `pantavisor-starter` built (the factory-flash machines, see below)
declares the extra targets as `extra_targets` in its `machines.json` entry
rather than swapping in a different base fragment.

`makemachines` resolves each fragment's `SRCREV` pins, appends `extra_targets`
to the dumped `target:` list, and writes a single self-contained
`kas/build-configs/release/<name>-scarthgap.yaml` that can reproduce the build
without network access to layer repos.

## USB Factory-Flash Machines (Toradex, Variscite, NXP MEK, Rockchip)

These machines build `pv-flash-bundle`, a self-contained over-USB factory-flash
archive (NXP i.MX via UUU, Rockchip via `rkdeveloptool`), instead of shipping a
bare `.wic`. See [pv-flash-bundle](../pv-flash-bundle.md) for how the recipe
itself works.

Each of these machines sets `extra_targets` in its `machines.json` entry;
`makemachines` appends them to the release yaml's `target:` list.

`verdin-imx8mm` and `colibri-imx6ull` add two extras — a recovery U-Boot is
needed because meta-pantavisor's `pv.distroboot.cfg` overrides the production
bootcmd:

```json
"extra_targets": ["mc:tezi-recovery:u-boot-toradex", "pv-flash-bundle"]
```

so the generated `target:` list is:

```yaml
target:
- pantavisor-starter
- mc:tezi-recovery:u-boot-toradex
- pv-flash-bundle
```

The `tezi-recovery` multiconfig (`DISTRO = "tezi"`, enabled by
`BBMULTICONFIG:append` in `kas/platforms/toradex.yaml`) builds the recovery
U-Boot used to enter fastboot mode during UUU flashing. Its output lands in
`tmp-scarthgap-tezi-recovery/` and is picked up by `pv-flash-bundle`.

`imx8mm-var-dart`, `imx8mn-var-som`, `imx8qxp-b0-mek` and `rockchip-orangepi-5b`
add just `pv-flash-bundle` — no recovery multiconfig. The NXP boards' production
bootloaders already self-enter SDP/fastboot download mode; the Rockchip board
uses `rkdeveloptool` + USB Maskrom, which needs no recovery build either:

```json
"extra_targets": ["pv-flash-bundle"]
```

All six machines set `"build_target": ""` (so `kas build` runs with no
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

See [docs/ci/builds.md — USB Factory-Flash Builds](builds.md#usb-factory-flash-builds-toradex-variscite-nxp-mek-rockchip),
[docs/how-to-install/toradex.md](../../getting-started/how-to-install/toradex.md),
[docs/how-to-install/uuu.md](../../getting-started/how-to-install/uuu.md), and
[docs/how-to-install/rockchip.md](../../getting-started/how-to-install/rockchip.md) for the
flash bundle contents and flashing procedures.

## Automated Machine Updates

`schedule-updatemachines.yaml` runs every 8 hours (offset by 15 minutes from `schedule-updates.yaml`) and executes `makemachines && makeworkflows` inside the KAS container. If the output differs from HEAD, it opens a PR on `autopr/machine-update-master-next`.
