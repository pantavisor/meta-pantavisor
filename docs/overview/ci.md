# CI/CD Overview

GitHub Actions workflows in `.github/workflows/` automate builds for all supported machines.

## Workflow Types

| Workflow type | Trigger | Use case |
|---------------|---------|---------|
| `manual` | GitHub Actions UI | On-demand builds |
| `tag` | Git tags | Release builds |
| `onpush` | Every push | Continuous validation (use sparingly, only for key machines) |

Reusable workflows:
- `buildkas-target.yaml` — Reusable build workflow
- `buildkas-upload.yaml` — Artifact upload to S3

## Machine Configuration

All machines are defined in `.github/machines.json`. This file is the single source of truth — workflow files are **generated** from it.

### Adding or Modifying a Machine

**Always follow this three-step process:**

1. **Edit `.github/machines.json`**:
   ```json
   {
       "config": "kas/machines/MACHINE.yaml:kas/scarthgap.yaml:kas/bsp-base.yaml:.github/configs/build-base-starter.yaml",
       "name": "MACHINE-NAME",
       "workflows": ["manual", "tag"]
   }
   ```

2. **Regenerate workflows**:
   ```bash
   .github/scripts/makeworkflows
   ```

3. **Commit both** — always commit `machines.json` and the generated workflow files together.

### Optional Machine Properties

| Property | Description |
|----------|-------------|
| `sdk: 1` | Build SDK for this machine |
| `output: "pattern"` | Custom output file pattern |
| `build_target: "recipe"` | Override default build target |

## Kconfig and Machine Configs

After modifying `Kconfig`, regenerate the per-machine config files:

```bash
.github/scripts/makemachines
```

Commit the updated machine config files alongside the Kconfig change.
