# Build Pipeline

## Build Engines

Two reusable workflows handle all builds. They share the same runner setup and KAS invocation but differ in what happens with the output.

### buildkas-target.yaml — development builds

Used by `onpush-scarthgap.yaml`, `manual-scarthgap.yaml`, `schedule-pvtests.yaml`, and `manual-pvtests.yaml`.

- Runs `kas build` inside the KAS container on a self-hosted runner.
- Copies build artifacts to GitHub Actions artifacts (wic images, pvrexports, SDK, pvtest-distro).
- **Does not upload to S3** and does not create a GitHub Release.

### buildkas-upload.yaml — release builds

Used by `release.yaml` (tag builds only).

- Same build steps as `buildkas-target.yaml`.
- Additionally calls `upload.sh` to push artifacts to S3 and update `releases.json`.

### Runner environment

| Detail | Value |
|---|---|
| Runner label | `self-hosted` |
| Container image | `ghcr.io/pantacor/kas/kas:next-v7` |
| sstate cache | `/shared/sstate` (Docker volume `shared`) |
| Download dir | `/shared/dldir` (Docker volume `shared`) |
| Build user | `builder` (non-root, container switches with `su - builder`) |
| Temp dir | `tmp-scarthgap` |

## Artifacts

Every build produces some subset of the following:

| Artifact name | Contents | Engine |
|---|---|---|
| `<target>-<machine>` | wic flash image (`*.rootfs.wic*`) | both |
| `pvrexports-<machine>` | pvrexport tarballs (`*pvrexport.tgz`) | both |
| `pantavisor-bsp-<machine>` | BSP pvrexport only | both |
| `pvtest-distro-<machine>` | unpacked appengine distro directory | both |
| `tezi-<target>-<machine>` | Toradex TEZI image (`*pv_teziimg.tar.xz`) | both |
| `sdk-artifact-<machine>` | Yocto SDK installer (`panta*.sh`) | both |

## S3 Distribution (upload.sh)

`upload.sh` is called by `buildkas-upload.yaml` once per machine. It:

1. Bundles the wic image and pvrexports into a tarball.
2. Pushes the bundle to `s3://<BUCKET>/meta-pantavisor/<TAG>/<MACHINE>/`.
3. Reads the existing `releases.json` from S3, upserts the machine entry under `devices`, sets `release-date` on first write, and uploads the file back.

`releases.json` is the discovery index used by the Pantavisor ecosystem to find the latest image URLs and SHA256 checksums. Schema:

```json
{
  "stable": {
    "029": {
      "release-date": "2026-06-03T10:00+00:00",
      "docs": {
        "name": "pantavisor-<rest>.docs.tar.zst",
        "hash": "<sha256>",
        "url": "https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/029/pantavisor-<rest>.docs.tar.zst"
      },
      "devices": [
        {
          "name": "raspberrypi-armv8-scarthgap",
          "full_image": { "url": "https://.../029/raspberrypi-armv8-scarthgap/raspberrypi-armv8-scarthgap-029.tar.gz", "sha256": "<sha256>" },
          "pvrexports":  { "url": "https://.../pvexports-raspberrypi-armv8-scarthgap-029.tar.gz",                      "sha256": "<sha256>" },
          "bsp":         { "url": "https://.../pantavisor-bsp-....pvrexport.tgz",                                      "sha256": "<sha256>" },
          "sdk":         { "url": "https://.../panta-....sh",                                                           "sha256": "<sha256>" }
        }
      ]
    }
  },
  "release-candidate": {
    "029-rc1": {
      "release-date": "2026-05-30T08:00+00:00",
      "docs": { "name": "...", "hash": "...", "url": "..." },
      "devices": [ "..." ]
    }
  }
}
```

`release-date` is set by the first machine job to finish (using `//=`) and left unchanged by subsequent parallel jobs. The `docs` key is written later by `tag-docs-scarthgap.yaml`.

### S3 path layout

```
s3://<BUCKET>/meta-pantavisor/
  <tag>/
    <machine>/                     ← bundle for this specific tag + machine
    pantavisor-<rest>.docs.tar.zst ← combined docs tarball for this tag
  latest/
    stable/
      badges/           ← per-machine badge JSON, updated after every stable tag build
    release-candidate/
      badges/           ← per-machine badge JSON, updated after every RC tag build
```

### Stable vs release-candidate classification

`upload.sh` and `upload-badges` both check whether the tag contains `-rc`:

| Tag pattern | Classification | S3 latest path |
|---|---|---|
| `028`, `029` | stable | `latest/stable/` |
| `028-rc1`, `028-rc9` | release-candidate | `latest/release-candidate/` |

## Documentation Tarball (tag-docs-scarthgap.yaml)

`tag-docs-scarthgap.yaml` runs via `workflow_run` after the `ontag: sync and
release` workflow (`tag-scarthgap.yaml`) completes successfully. It is
independent of the per-machine build matrix.

Documentation is built using `pantavisor-docs.bbclass` and
`pantacor-component-docs.bbclass`. See
[how-to-build/component-docs.md](../how-to-build/component-docs.md) for the
full class reference.

The job:

1. Checks out the tagged commit (`workflow_run.head_sha`) so the docs match
   the release.
2. Runs `kas build kas/build-configs/release/raspberrypi-armv8-scarthgap.yaml -- -c create_pantacor_docs pantavisor-starter`
   inside the KAS container. `raspberrypi-armv8-scarthgap.yaml` was chosen
   because `pantavisor-starter` is its primary target and it pulls in the full
   set of components — including `pvr` (used by the pantabox container) — that
   need documentation. The `pantavisor-docs` image class triggers
   `do_create_component_docs` for every package in the image's dependency tree
   (via `[recrdeptask]`), collects the resulting per-component tarballs, adds
   `meta-pantavisor/docs/`, and packages everything into a single
   `<IMAGE_LINK_NAME>.rootfs.docs.tar.zst`. No full image assembly is needed —
   BitBake only builds packages up to `do_install`.
3. Collects the real tarball (non-symlink `*.rootfs.docs.tar.zst`) from
   `build/tmp-scarthgap/deploy/images/`.
4. Renames the tarball: `pantavisor-starter-<rest>.rootfs.docs.tar.zst` →
   `pantavisor-<rest>.docs.tar.zst` (strips `starter-` and `.rootfs`).
5. Uploads the renamed tarball directly under the tag prefix in S3:
   ```
   s3://<BUCKET>/meta-pantavisor/<TAG>/pantavisor-<rest>.docs.tar.zst
   ```
6. Downloads `releases.json` from S3, upserts a `docs` key at the tag level,
   and writes it back. Machine entries written by `upload.sh` live under
   `devices` in the same object:

```json
{
  "release-candidate": {
    "028-rc10": {
      "release-date": "2026-05-13T21:27+00:00",
      "docs": {
        "name": "pantavisor-<rest>.docs.tar.zst",
        "hash": "<sha256>",
        "url": "https://pantavisor-ci.s3.amazonaws.com/meta-pantavisor/028-rc10/pantavisor-<rest>.docs.tar.zst"
      },
      "devices": [
        { "name": "sunxi-orange-pi-3lts-scarthgap", "full_image": {}, ... },
        ...
      ]
    }
  }
}
```

7. Uploads the original (unstripped) tarball to the GitHub Release via
   `upload-docs.py upload-asset`, then sends a `repository_dispatch` event
   (`event_type: "docs-release"`, payload `{"tag": "<TAG>"}`) directly to
   `pantavisor/docs.pantavisor` via `curl` using the `PANTAVISOR_DOC_SYNC`
   secret.

The tag is taken from `workflow_run.head_branch` (the tag that triggered
`tag-scarthgap.yaml`). Because `workflow_run` only fires for workflow files
present on the default branch, this workflow takes effect once it is on
`master`.

## CI Badges (upload-badges)

After all build jobs finish, the `summary` job in `release.yaml` calls `upload-badges`. The script:

1. Queries the GitHub API for all jobs in the current run that match `contains("build (")`.
2. Maps each job's conclusion to a shields.io color (`brightgreen` / `red` / `lightgrey` / `yellow`).
3. Writes a JSON file per machine: `{"schemaVersion":1,"label":"<machine>","message":"passing","color":"brightgreen"}`.
4. Uploads each JSON to `s3://<BUCKET>/meta-pantavisor/latest/<stable|release-candidate>/badges/<machine>.json`.
5. Uploads a `tag.json` badge showing the tag name.

The badge URLs in `README.md` and `docs/ci/status.md` point to these S3 objects via `https://img.shields.io/endpoint?url=<S3-URL>`. Shields.io fetches the JSON on render and produces an SVG badge.

## pvtests Pipeline

pvtests run against the `docker-x86_64-scarthgap` appengine distro image. They require a dedicated `pvtest-runner` runner with Docker available.

The `call-pvtests.yaml` reusable workflow:

1. Downloads the `pvtest-distro-docker-x86_64-scarthgap` artifact.
2. Installs Docker images via `test.docker.sh install-docker`.
3. Runs `test.docker.sh run <test_path>` with `--retry 3` for remote tests.
4. Appends the SUMMARY section of `test.docker.log` to the step summary.
5. Uploads the pvtest workspace (logs, valgrind output) as an artifact.
6. Cleans up Docker containers and images.

`test_path` controls which tests run:
- `local` — tests that run entirely on the runner (no network to Pantahub)
- `remote` — tests that connect to Pantahub (require `PH_USER`/`PH_PASS` secrets)
- empty — run all tests

In `release.yaml`, `pvtest-remote` runs with `if: always()` so it executes even if `pvtest-local` fails, and its results don't block the `summary` job.

## Component Auto-Updates

`schedule-updates.yaml` runs `update-components.sh` every 8 hours. The script reads `.github/scripts/components.json`, which lists each tracked component with its recipe glob, upstream branch, and GitHub org. For each component:

1. Fetches the latest commit SHA from the upstream branch via `git ls-remote`.
2. If the SHA differs from the current `SRCREV` in the recipe, updates the recipe in-place.
3. Appends a short git log to the commit message body for review.

If any updates were found, the workflow opens (or force-updates) a PR on `auto-update/components`.
