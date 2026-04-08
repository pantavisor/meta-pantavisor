# pvtx Unit Test Plan

Tests for the **pvtx** transaction tool that manages Pantavisor revision state.

Unlike the xconnect and pvctrl test plans (which require a running Pantavisor
instance), pvtx tests are **unit tests** — they only need the `pvtx` binary and
standard shell utilities (`jq`, `xxd`, `bc`).  They can be run:

- **From the Pantavisor source tree** using CMake/CTest (no container needed)
- **Inside the appengine container** using the helper script below

The test suite lives at `test/pvtx/pvtx.sh` in the Pantavisor repository and is
applied to the Yocto build via
`recipes-pv/pantavisor/files/0001-test-pvtx-enhance-test-suite.patch`.

The patch also exists at `patches/pantavisor/0001-test-pvtx-enhance-test-suite.patch`
for direct submission to the Pantavisor upstream repository.

---

## Tests Covered

| Test | Description |
|------|-------------|
| `test_create_empty_transaction` | `pvtx begin empty` → show equals canonical empty state |
| `test_process_json_keys_with_spaces` | Keys containing spaces round-trip intact |
| `test_signature_removal` | Remove sig by sig path (`_sigs/`) |
| `test_signature_removal2` | Remove sig by container name |
| `test_signature_removal3` | Remove sig by `_config/` path |
| `test_removal_config_pkg` | Remove a config package signature |
| `test_package_update` | Re-adding an existing container updates its entry |
| `test_add_package_from_tar` | Add container from a `.tar` archive |
| `test_add_new_package` | Add a previously-absent container |
| `test_add_new_package_from_cat` | Add container via stdin pipe (production use case) |
| `test_update_bsp` | BSP object update merges correctly |
| `test_update_bsp_with_groups` | BSP update with separate `groups.json` |
| `test_install_from_tgz` | Install OS container from `.tar.gz` |
| `test_two_package_signing_same_files` | Two packages claiming the same files; remove one sig |
| `test_two_package_signing_same_files_with_globs` | Same as above with glob patterns |
| `test_removal_of_signed_config` | Config addition followed by config removal |
| `test_queue_new` | Queue `.status` binary layout is correct |
| `test_queue_actions` | Queue remove writes correctly named action files |
| `test_queue_process` | Full queue workflow (new → unpack → begin → process) — **offline** |
| `test_queue_process_with_remove` | Queue remove action applied via process |
| `test_deploy` | `pvtx deploy` writes `.pvr/json` matching show output |
| `test_process_queue_without_begin` | Queue process with implicit `empty` begin |
| `test_local_transaction` | Local transaction (objects path set) cannot be committed |
| `test_empty_transaction_has_spec` | Empty state always carries `#spec` field |
| `test_show_is_idempotent` | Consecutive `pvtx show` calls produce identical output |
| `test_spec_preserved_after_remove` | `#spec` survives a container removal |
| `test_add_state_roundtrip` | `add` then `show` equals the original input |
| `test_double_add_is_idempotent` | Adding the same state twice is a no-op |
| `test_abort_clears_transaction` | `abort` followed by `begin empty` yields clean empty state |

Every test that captures `pvtx show` JSON also runs **`check_canonical_json`**
which verifies:

1. The output is valid, parseable JSON
2. The mandatory `#spec` field is present
3. `jq -S .` applied twice yields the same bytes (idempotent normalisation)

---

## Option A — From Pantavisor Source Tree (CMake / CTest)

This is the recommended path when developing or patching the pantavisor source
directly.

### Prerequisites

- CMake ≥ 3.0
- Pantavisor built with `-DPANTAVISOR_PVTX=ON` (the default)
- `jq`, `xxd`, `bc`, `tar`, `mktemp` in PATH

### Build

```bash
git clone https://github.com/pantavisor/pantavisor.git
cd pantavisor

# Apply the patch (until it lands upstream)
git apply /path/to/meta-pv-pvtx/patches/pantavisor/0001-test-pvtx-enhance-test-suite.patch

mkdir build && cd build
cmake .. -DPANTAVISOR_PVTX=ON -DPANTAVISOR_PVTX_STATIC=ON
make -j$(nproc) pvtx
```

### Run All pvtx Tests

```bash
# From the build directory:
ctest -R pvtx -V
```

### Run with Verbose pvtx Output

```bash
PVTX_TEST_PRINT_ALL=1 ctest -R pvtx -V
```

### Run Manually (without CTest)

```bash
# From the build directory:
../test/pvtx/pvtx.sh .. .
```

### Expected Output

```
test_create_empty_transaction                      [OK]
test_create_empty_transaction_canonical            [OK]
test_process_json_keys_with_spaces                 [OK]
test_process_json_keys_with_spaces_canonical       [OK]
...
test_abort_clears_transaction                      [OK]
test_abort_clears_transaction_canonical            [OK]
```

Every test line appears twice — the functional check followed by its canonical
JSON validation.

---

## Option B — Inside Appengine Container (meta-pantavisor)

This path tests the same pvtx binary that will ship in a Yocto image.

### Prerequisites

Build the appengine image (the `pantavisor-pvtest` package installs `pvtx`,
the test script, and all test data into the image):

```bash
./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml

docker load < build/tmp-scarthgap/deploy/images/docker-x86_64/pantavisor-appengine-docker.tar
```

### Launch Container (Test Mode — No Pantavisor Needed)

pvtx tests do **not** require Pantavisor to be running:

```bash
docker rm -f pva-pvtx 2>/dev/null

docker run --name pva-pvtx -d --rm \
    --entrypoint /bin/sh pantavisor-appengine:latest -c "sleep infinity"
```

### Run the Test Suite

```bash
docker exec pva-pvtx sh -c '
    PVTX_BIN_DIR=$(dirname $(command -v pvtx))
    TEST_DATA=/usr/share/pantavisor/pvtest/pvtx
    TMPDIR=$(mktemp -d)
    export PVTXDIR="${TMPDIR}/pvtxdir"
    mkdir -p "${PVTXDIR}"
    /usr/share/pantavisor/pvtest/pvtx/pvtx.sh "${TEST_DATA}/.." "${PVTX_BIN_DIR}"
    rm -rf "${TMPDIR}"
'
```

Or use the convenience wrapper (see `tools/run-pvtx-tests.sh`):

```bash
./tools/run-pvtx-tests.sh
```

### Teardown

```bash
docker rm -f pva-pvtx
```

---

## Convenience Wrapper Script

`tools/run-pvtx-tests.sh` automates Option B:

```bash
./tools/run-pvtx-tests.sh                 # uses default image tag
./tools/run-pvtx-tests.sh 1.0             # override image tag
PVTX_TEST_PRINT_ALL=1 ./tools/run-pvtx-tests.sh   # verbose pvtx output
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `pvtx: not found` | pvtx not installed | Build with `-DPANTAVISOR_PVTX=ON` or use appengine image |
| `jq: not found` | jq missing | Install `jq` on host, or use appengine image |
| `couldn't find .../test/pvtx` | Wrong SRC_DIR argument | Pass the pantavisor repo root as first argument to pvtx.sh |
| Test data missing in container | `pantavisor-pvtest` not included | Rebuild image; check `IMAGE_INSTALL` includes `pantavisor-pvtest` |
| `check_canonical_json` fails with `#spec missing` | pvtx dropped the spec field | Check the pvtx transaction merge logic for the failing test case |
| `check_canonical_json` fails idempotency check | jq or pvtx produces non-normalised JSON | Run `jq -S . < result.json` twice and compare |
