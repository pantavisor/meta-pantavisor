# Automated Test Workflow

Structured testing using `test.docker.sh` — the test runner bundled inside the `pantavisor-appengine-distro` build target. Use this for running test plans, collecting valgrind results, and CI validation. For the manual development workflow (quick iteration while coding), see [development-workflow.md](development-workflow.md).

## Build

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml \
    --target pantavisor-appengine-distro
```

Output: `build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-distro-docker-x86_64-*.tar.gz`

## Install

Extract the tarball and load the Docker images into a working directory:

```bash
mkdir -p <workdir> && cd <workdir>
tar -xvf /path/to/pantavisor-appengine-distro-docker-x86_64-*.tar.gz
chmod +x test.docker.sh
./test.docker.sh install-docker      # loads appengine, tester, and netsim images

# Clone test repos (first time only)
git clone git@gitlab.com:pantacor/pvtests-local.git
git clone git@gitlab.com:pantacor/pvtests-remote.git
```

Remote tests require `PH_USER` and `PH_PASS` in the environment (or a sourced `.env` file).

## Running tests

```bash
# List available tests
./test.docker.sh -v ls

# Run a specific test (with valgrind)
./test.docker.sh -v run pvtests-local:000 -V

# Run all tests in a group
./test.docker.sh -v run pvtests-local -V

# Run all tests across all groups
./test.docker.sh -v run -V
```

Logs land in `./test.docker.log`. Pantavisor storage is preserved at `<tmpdir>/storage/<group>/<number>/` for post-run inspection.

## Debugging a failing test

```bash
# Interactive shell — Pantavisor starts normally; shell opens once it reaches READY
# (and claims the device if credentials are configured).
# Use when Pantavisor boots fine but you want to inspect the running state.
./test.docker.sh -v run pvtests-local:000 -i

# Manual shell — container starts but Pantavisor does NOT run.
# Use when Pantavisor fails to reach READY and you need to debug the startup sequence.
./test.docker.sh -v run pvtests-local:000 -m
```

Both `-i` and `-m` require a specific test number (not a group).

## Authoring and updating tests

```bash
# Create a new test scaffold in a group
./test.docker.sh add pvtests-local

# Regenerate expected output for an existing test
./test.docker.sh -v run pvtests-local:000 -o
```

## test.docker.sh flags reference

**Global options** (before the command):

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable debug output and print a results summary at the end |
| `-d <dir>`, `--dir <dir>` | Use `<dir>` as the pvtest source directory (overrides `PVTEST_DIR` env) |

**`run` arguments** (after the group/test selector):

| Flag | Description |
|------|-------------|
| `-V`, `--valgrind` | Run Pantavisor under valgrind; results saved to `<tmpdir>/valgrind/` |
| `-i`, `--interactive` | Open a shell once Pantavisor reaches READY (device claimed if configured). Use to inspect a working system. Requires a specific test number. |
| `-m`, `--manual` | Open a shell without starting Pantavisor. Use when PV fails to reach READY and you need to debug startup. Requires a specific test number. |
| `-o`, `--overwrite` | Create or overwrite the expected test output (use when authoring or updating tests) |
| `-n`, `--netsim` | Enable wireless network simulation via `mac80211_hwsim` (experimental) |

**Exit codes**: `0` = PASSED, `1` = FAILED, `2` = ABORTED

## Test plans

Test plans covering specific features live in [testplans/](testplans/):

| Plan | Coverage |
|------|----------|
| [testplan-auto-recovery.md](testplans/testplan-auto-recovery.md) | Container restart policies, exponential backoff, group inheritance |
| [testplan-container-control.md](testplans/testplan-container-control.md) | Container lifecycle API (stop/start/restart, user_stopped, batch jobs) |
| [testplan-pvctrl.md](testplans/testplan-pvctrl.md) | Full pv-ctrl REST API coverage |
| [testplan-xconnect.md](testplans/testplan-xconnect.md) | xconnect service mesh (unix, D-Bus, DRM) |
