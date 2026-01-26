# Pantavisor GitHub Workflow Infrastructure

This directory contains the Template-Driven CI/CD framework for Pantavisor. Instead of manual YAML maintenance, this system uses a central "Source of Truth" configuration to automate the generation of Yocto builds across multiple hardware architectures.

## Folder Structure

* **configs/**: Modular Kas configuration files.
    * **release/**: Auto-generated standalone YAMLs containing pinned Git SHAs for reproducible builds.
* **scripts/**: The automation engine.
    * **makemachines**: Flattens modular Kas configs into release-ready files.
    * **makeworkflows**: Generates GitHub Actions from blueprints in the `template/` folder.
    * **makecommit**: Audits layer changes and generates detailed PR descriptions with git logs.
* **template/**: Blueprint YAML files (`manual`, `onpush`, `tag`) used to generate the final workflows.
* **workflows/**: The execution layer.
    * **buildkas-target.yaml**: Reusable logic for standard builds.
    * **buildkas-upload.yaml**: Reusable logic for releases and cloud uploads.
    * **upload.sh**: Script to synchronize artifacts with Amazon S3 and update the global `releases.json`.
    * **[Generated Workflows]**: Machine-specific triggers created by `makeworkflows`.

---

## The Source of Truth: machines.json

All CI behavior is controlled via `machines.json`.

| Key | Description |
| :--- | :--- |
| yocto_branch | The Yocto release version (e.g., `scarthgap`). |
| config | A colon-separated string of Kas files to inherit. |
| workflows | Triggers to generate: `manual`, `onpush`, or `tag`. |
| build_target | Optional: The specific BitBake target to build. |
| sdk | Set to `1` to enable Yocto SDK toolchain generation. |
| output | Glob pattern for the specific image artifacts to collect. |


---

## Maintenance Workflows

### 1. Adding a New Machine/Board
To add support for a new hardware target:
1. Open `machines.json` and add a new entry to the `machines` array.
2. Run the generation scripts to manifest the changes:
   ```bash
   ./.github/scripts/makemachines
   ./.github/scripts/makeworkflows
   ```

3. Commit the changes in `machines.json`, .`github/configs/release/`, and `.github/workflows/`.

### 2. Updating Layer Revisions (The "Bumping" Process)
**Automated:**
The `updatemachines.yaml` workflow runs automatically on a schedule (every 8 hours) to check for updates. If new commits are found in the upstream layers, it executes the scripts below and opens a Pull Request with the changes.

**Manual:**
To manually update the underlying Yocto layers (meta-pantavisor, poky, etc.) to their latest branch commits:

1. Run the machine generator to refresh the SHAs:
   ```bash
   ./.github/scripts/makemachines
   ```

2. Use the commit script to generate a human-readable changelog of all layer updates:
   ```bash
   ./.github/scripts/makecommit
   ```

This script performs a git fetch on changed repos and lists every new commit SHA in the PR body for easy auditing.

## Reusable Workflow Logic
We utilize Workflow Call (`workflow_call`) to keep logic DRY (Don't Repeat Yourself).

### Build Engine (buildkas-target.yaml)
Used for **Manual** and **On-Push** builds. It handles workspace setup on self-hosted runners, executes the `kas build`, and stores images as GitHub Action artifacts for internal testing.

### Release Engine (buildkas-upload.yaml)
Used when a **Git Tag** is pushed. It extends the build engine by:

1.  Generating Markdown release notes.
2.  Creating an official GitHub Release.
3.  Invoking `./.github/workflows/upload.sh` to propagate artifacts to S3.


---

## Artifact Distribution (upload.sh)
The upload script ensures that our public distribution network stays up to date:

* **Storage**: Artifacts are bundled and pushed to `s3://[BUCKET]/[TAG]/[MACHINE]/`.
* **Metadata**: It categorizes releases as **stable** (e.g., versions starting with `0`) or **release-candidate** (versions containing `-rc`).
* **Indexing**: It updates the central `releases.json` on S3, allowing the Pantavisor ecosystem to discover new images and their corresponding SHA256 checksums automatically.
