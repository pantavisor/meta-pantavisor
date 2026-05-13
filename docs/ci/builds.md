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
3. Reads the existing `releases.json` from S3, appends an entry for this machine/tag, and writes it back.

`releases.json` is the discovery index used by the Pantavisor ecosystem to find the latest image URLs and SHA256 checksums.

### S3 path layout

```
s3://<BUCKET>/meta-pantavisor/
  <tag>/
    <machine>/          ← bundle for this specific tag + machine
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
