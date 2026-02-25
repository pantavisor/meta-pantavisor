# TESTPLAN: EFI A/B Boot (x64-efi) — v2

Executable test plan using `pv-qemu-tool.sh` primitives.
Each test case contains the exact commands an AI agent or CI script runs.

## Prerequisites

### Build

```bash
# Full build (with workspace pantavisor)
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml:kas/with-workspace.yaml

# Full build (upstream sources)
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml
```

### Tool location

```bash
TOOL=./scripts/pv-qemu-tool.sh
```

## Session Lifecycle

```bash
# Start a session (prints session ID to stdout)
ID=$($TOOL start --name efiab-test)

# ... run test cases ...

# Cleanup
$TOOL stop "$ID"
```

## Test Cases

### TC-1: EFI boot chain

Verify OVMF loads stage1, stage1 loads stage2, stage2 loads UKI, kernel boots.

**Steps:**

```bash
ID=$($TOOL start --name tc1)
$TOOL wait "$ID" "pv-efi-boot stage1" --timeout 60
$TOOL wait "$ID" "pv-efi-boot stage2" --timeout 30
$TOOL wait "$ID" "Pantavisor" --timeout 60
$TOOL stop "$ID"
```

**Pass:** All three `wait` commands return `OK`.
**Fail:** Any `wait` returns `TIMEOUT`.

---

### TC-2: Pantavisor storage mount

Verify ext4 root partition is mounted and pantavisor starts without fatal errors.

**Steps:**

```bash
ID=$($TOOL start --name tc2)
$TOOL wait-shell "$ID" --timeout 120
$TOOL exec "$ID" "mount | grep sda4"
$TOOL exec "$ID" "dmesg | grep -i 'EXT4-fs (sda4)'"
$TOOL stop "$ID"
```

**Pass:** `mount` output contains `/dev/sda4` with `ext4`. No `FATAL` in `dmesg`.
**Fail:** Mount line missing or shows errors.

---

### TC-3: Pantavisor reaches STATE_WAIT

Verify pantavisor progresses through STATE_INIT to STATE_WAIT.

**Steps:**

```bash
ID=$($TOOL start --name tc3)
$TOOL wait-shell "$ID" --timeout 120
$TOOL exec "$ID" "grep 'STATE_WAIT' /storage/logs/0/pantavisor/pantavisor.log | head -3"
$TOOL stop "$ID"
```

**Pass:** Output contains `STATE_WAIT`.
**Fail:** No match or only `STATE_INIT`.

---

### TC-4: PV_BOOTLOADER_TYPE is efiab

Verify pantavisor detects the EFI A/B bootloader type.

**Steps:**

```bash
ID=$($TOOL start --name tc4)
$TOOL wait-shell "$ID" --timeout 120
$TOOL exec "$ID" "grep PV_BOOTLOADER_TYPE /storage/logs/0/pantavisor/pantavisor.log | head -1"
$TOOL stop "$ID"
```

**Pass:** Output contains `'efiab'`.
**Fail:** Output contains `'uboot'` or is empty.

---

### TC-5: Containers start

Verify LXC containers start after pantavisor reaches run state.

**Steps:**

```bash
ID=$($TOOL start --name tc5)
$TOOL wait-shell "$ID" --timeout 120
# Wait for containers to settle
$TOOL exec "$ID" "sleep 10" --timeout 15
$TOOL exec "$ID" "pvcontrol ls" --timeout 10
$TOOL stop "$ID"
```

**Pass:** `pvcontrol ls` lists `pv-alpine-connman` and/or `pv-pvr-sdk`.
**Fail:** No containers listed or command errors.

---

### TC-6: Debug shell access

Verify the debug shell prompt appears and is functional.

**Steps:**

```bash
ID=$($TOOL start --name tc6)
$TOOL wait-shell "$ID" --timeout 120
$TOOL exec "$ID" "uname -a"
$TOOL exec "$ID" "cat /proc/cmdline"
$TOOL exec "$ID" "lsblk"
$TOOL stop "$ID"
```

**Pass:** `wait-shell` returns `OK`. All `exec` commands return exit code 0 with
valid output (kernel version, cmdline with `pv_PV_BOOTLOADER_TYPE=efiab`, block devices).
**Fail:** `wait-shell` returns `TIMEOUT`, or `exec` returns nonzero.

---

### TC-7: EFI A/B update cycle via pvcontrol

Full update lifecycle: create revision, trigger update, verify reboot, check logs.

**Steps:**

```bash
ID=$($TOOL start --name tc7)
$TOOL wait-shell "$ID" --timeout 120

# Step 1: Get current state
$TOOL exec "$ID" "pvcontrol steps get current > /tmp/current.json 2>&1" --timeout 30
$TOOL exec "$ID" "test -s /tmp/current.json"

# Step 2: Create modified state (inject reboot.json to trigger BSP-level diff)
$TOOL exec "$ID" \
  "sed 's|\"bsp/src.json\":{}|\"bsp/src.json\":{},\"reboot.json\":{}|' /tmp/current.json > /tmp/new.json"
$TOOL exec "$ID" "grep -q 'reboot.json' /tmp/new.json"

# Step 3: Upload as local revision
$TOOL exec "$ID" "pvcontrol steps put /tmp/new.json locals/test-1 > /tmp/put-out.txt 2>&1" --timeout 30
$TOOL exec "$ID" "! grep -qi error /tmp/put-out.txt"

# Step 4: Trigger update and exit shell so reboot can proceed
$TOOL exec "$ID" "pvcontrol commands run locals/test-1 2>&1" --timeout 10
$TOOL exec "$ID" "sleep 2; exit" --timeout 10

# Step 5: Wait for reboot (stage1 reappears)
$TOOL wait "$ID" "pv-efi-boot stage1" --timeout 90

# Step 6: Enter debug shell on second boot
$TOOL wait-shell "$ID" --timeout 120

# Step 7: Verify update milestones in log
$TOOL exec "$ID" "grep -q 'Install update prepared' /storage/logs/0/pantavisor/pantavisor.log" --timeout 10
$TOOL exec "$ID" "grep -q 'pv_rev.txt written successfully' /storage/logs/0/pantavisor/pantavisor.log" --timeout 10
$TOOL exec "$ID" "grep -q 'pv_try set to' /storage/logs/0/pantavisor/pantavisor.log" --timeout 10

# Diagnostic output
$TOOL exec "$ID" \
  "grep -E 'efiab|tryboot|pv_try|install_update|commit|reboot' /storage/logs/0/pantavisor/pantavisor.log | tail -25" \
  --timeout 10

$TOOL stop "$ID"
```

**Pass:** All `exec` commands return exit code 0. `wait` for `stage1` returns `OK`.
Post-reboot log checks find `Install update prepared`, `pv_rev.txt written`, `pv_try set`.
**Fail:** Any step returns nonzero or times out.

**Known limitation:** Stage1 does not yet read `PvTryBoot` EFI variable.
After reboot, stage1 boots from the same partition (boot_a). Pantavisor detects
this as an "early rollback" scenario.

---

## Console Log Inspection

For any test case, the console log can be inspected after the fact:

```bash
# Full console output
$TOOL log "$ID"

# Filter for specific patterns
$TOOL log "$ID" --grep "efiab"
$TOOL log "$ID" --grep "FATAL|panic|error"
$TOOL log "$ID" --grep "pv-efi-boot"
```

## Batch Execution

Run all TCs in sequence, reusing a single session for TC-1 through TC-6
(TC-7 needs its own session due to reboot):

```bash
TOOL=./scripts/pv-qemu-tool.sh

echo "=== Starting shared session ==="
ID=$($TOOL start --name batch)

# TC-1: boot chain (wait for pantavisor as part of boot-up)
echo "--- TC-1: EFI boot chain ---"
$TOOL wait "$ID" "pv-efi-boot stage1" --timeout 60 && echo "  stage1 OK"
$TOOL wait "$ID" "pv-efi-boot stage2" --timeout 30 && echo "  stage2 OK"
$TOOL wait "$ID" "Pantavisor" --timeout 60 && echo "  pantavisor OK"

# TC-6: debug shell (also enters shell for subsequent TCs)
echo "--- TC-6: Debug shell ---"
$TOOL wait-shell "$ID" --timeout 120 && echo "  shell OK"
$TOOL exec "$ID" "uname -a" && echo "  uname OK"

# TC-2: storage mount
echo "--- TC-2: Storage mount ---"
$TOOL exec "$ID" "mount | grep sda4" && echo "  mount OK"

# TC-3: STATE_WAIT
echo "--- TC-3: STATE_WAIT ---"
$TOOL exec "$ID" "grep STATE_WAIT /storage/logs/0/pantavisor/pantavisor.log | head -1" && echo "  state OK"

# TC-4: bootloader type
echo "--- TC-4: Bootloader type ---"
$TOOL exec "$ID" "grep PV_BOOTLOADER_TYPE /storage/logs/0/pantavisor/pantavisor.log | head -1" && echo "  efiab OK"

# TC-5: containers
echo "--- TC-5: Containers ---"
$TOOL exec "$ID" "pvcontrol ls" --timeout 15 && echo "  containers OK"

$TOOL stop "$ID"

# TC-7: separate session (involves reboot)
echo "--- TC-7: Update cycle ---"
# ... (see TC-7 steps above)
```

## Key Files

| File | Purpose |
|------|---------|
| `scripts/pv-qemu-tool.sh` | CLI session manager |
| `scripts/pv-qemu-expect.sh` | Expect backend (FIFO protocol) |
| `scripts/run-qemu-efi.sh` | Standalone QEMU launcher (reference) |
| `scripts/test-update-efi.exp` | Monolithic update test (superseded by TC-7) |
| `TESTPLAN-efiab.md` | Original test plan (v1) |
