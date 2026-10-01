---
sidebar_position: 3.5
---
# Container Builds

Product containers (`pv-avahi`, `pv-tailscale`, `pv-mqtt-sdk`, ...) are built and published separately from the BSP images. The list lives in `.github/containers.json`; every workflow builds **all containers for one machine in a single kas run**, one `--target` per container, instead of one job per (container, machine) pair.

## containers.json

Each entry declares what to build and where it applies:

| Field | Meaning |
|---|---|
| `name` | Container name; used in artifact and S3 names |
| `machine` | Machines that build it (`docker-x86_64`, `docker-armv6`, `docker-armv8`) |
| `build_target` | Recipe passed to kas as `--target` (defaults to `name`) |
| `output` | pvrexport file the build produces, e.g. `pv-avahi.pvrexport.tgz` |
| `workflows` | `manual` and/or `tag`: which dispatch lists and release runs include it |
| `display_name`, `description` | Shown in `containers-releases.json` |

After editing it, regenerate the workflows and commit both together:

```bash
.github/scripts/makeworkflows
```

The container list for a tag build is resolved at run time, so adding a container to a machine that already builds containers needs no workflow regen (the manual dispatch dropdown does).

## Building locally

`.github/scripts/container-targets` is the single place that decides which containers build for a machine:

```bash
.github/scripts/container-targets docker-armv8
# --target pv-labutils --target pv-avahi --target pvwificonnect ...

./kas-container build $(.github/scripts/container-targets docker-x86_64) \
    kas/build-configs/release/containers/docker-x86_64-scarthgap.yaml -- -k
```

`--target` flags must come before the config, or kas rejects `-- -k`. Options:

```bash
container-targets --workflow tag <machine>             # only containers listed for "tag"
container-targets --container "pv-avahi pv-pvsm" <machine>
container-targets --list name <machine>                # one value per line: name|build_target|output
```

It prints nothing when no container matches, so callers treat empty as an error.

## Workflows

| Workflow | Trigger | What it builds | Output |
|---|---|---|---|
| `manual-containers-scarthgap.yaml` | `workflow_dispatch` | `machine` + `container` (default `all`) | One artifact per container |
| `release-containers.yaml` | tag push (via `tag-scarthgap.yaml`) | Every `tag` container, `docker-armv6`, then `docker-armv8`, then `docker-x86_64` | S3 + `containers-releases.json` |
| `onpush-containers.yaml` | push / `ready_for_review` touching `recipes-containers/**` | Only the containers that changed, on every machine each supports | One artifact per container, no S3 |

All three build with `-k`, so one broken recipe doesn't block the rest, and still publish whatever built.

### Manual dispatch

Pick the machine first; `container` defaults to `all`. Choosing a container the machine doesn't support (e.g. `pv-debian-nm` on `docker-armv8`) fails in the `resolve` job.

```bash
gh workflow run manual-containers-scarthgap.yaml \
    -f machine=docker-armv8 -f container=pv-avahi
```

The build yields one combined artifact; a follow-up `split` job republishes each pvrexport as `<container>-<machine>-scarthgap` and removes the combined zip.

### Tag release

`release-containers.yaml` runs 3 jobs, serialised with `max-parallel: 1`. Each job uploads every container that built (`upload-container.sh`) and writes a per-container ✅/❌ table to the job summary. `docker-x86_64` is included, so x86_64-only containers such as `pv-debian-nm` are published too.

`upload-container.sh` picks the file by the container's declared `output` (not the first pvrexport found) and exits non-zero if it is missing or the S3 copy fails, which marks that container ❌. Each uploaded container is recorded under its tag in `containers-releases.json` (at the root of the CI S3 bucket), with the pvrexport URL and sha256 per machine. The pvrexports themselves land under `containers/<tag>/<container>-<machine>-scarthgap/<container>-<arch>.pvrexport.tgz`.

### On push

`.github/scripts/changed-containers` maps changed paths (stdin) to container names, logging each decision to stderr:

```bash
git diff --name-only master...HEAD | .github/scripts/changed-containers
```

Rules:

- A file or any parent directory named after a container belongs to it, longest name wins (`pv-avahi-browse_1.0.bb` → `pv-avahi-browse`, `pv-labutils/packagegroup-pv-labutils.bb` → `pv-labutils`).
- A shared file matching no name belongs to the containers whose recipes reference its basename (`pantavisor/files/mdev.json` → `pv-alpine-connman pv-awconnect pv-debian-nm`).
- `pv-examples/` and `debug/` are not shipped containers and are ignored.

Branches with a draft PR are skipped, like `onpush-scarthgap`; run `gh pr ready` to build.

## Reusable workflows

| File | Role |
|---|---|
| `buildkas-containers.yaml` | Generated. `resolve` → `build` → `split`; called by the manual dispatch and `onpush-containers` |
| `buildkas-target.yaml` | `build_target` takes a space-separated list (one `--target` each); `keep_going` adds `-k` |
| `buildkas-upload-container.yaml` | Tag builds: kas build, S3 upload and summary table per machine |
