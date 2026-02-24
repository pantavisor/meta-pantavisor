# Test Plan: x64-efi EFI Boot (pantavisor-remix)

Executable test plan for the pantavisor-remix EFI A/B boot image on the x64-efi machine.

**Branch**: `feature/xconnect-landing`
**Machine**: `x64-efi`
**Distro**: `panta` (musl)

## Prerequisites

### Build

```bash
# Build with local workspace (recommended for development)
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml:kas/with-workspace.yaml

# Build from upstream sources
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml
```

Build output: `build/tmp-scarthgap/deploy/images/x64-efi/pantavisor-remix-x64-efi.rootfs.wic`

### QEMU scripts

| Script | Purpose |
|--------|---------|
| `scripts/run-qemu-efi.sh` | Interactive QEMU boot (Ctrl-A X to quit) |
| `scripts/run-qemu-efi.sh --timeout 60` | Non-interactive with timeout |
| `scripts/qemu-diag.exp <cmd> [cmd...]` | Automated: boot, enter debug shell, run commands, exit |

All scripts use Yocto-built `qemu-system-native` with the uninative loader. No host QEMU required.

---

## Test 1: Boot and Reach READY

**Purpose**: Verify full EFI boot chain and pantavisor reaching READY state.

### Execute

```bash
expect scripts/qemu-diag.exp \
  "grep -E 'STATE_|READY|status is now' /storage/logs/0/pantavisor/pantavisor.log | head -10"
```

### Verify

```
next state: 'STATE_RUN'
next state: 'STATE_WAIT'
group 'root' status is now READY
group 'platform' status is now READY
state revision '0' status is now READY
```

### Expected Results

| Check | Expected |
|-------|----------|
| EFI boot chain | `Pantavisor starting...` on serial console |
| STATE_RUN | Reached within ~5s |
| STATE_WAIT | Reached within ~10s |
| Group `root` | READY |
| Group `platform` | READY |
| Revision status | READY |
| Errors in log | `grep -c ERROR` returns 0 |

---

## Test 2: EFI Diagnostics

**Purpose**: Verify EFI-specific infrastructure: efivarfs, autoboot.txt, bootloader type, ESP access.

### Execute

```bash
expect scripts/qemu-diag.exp \
  "cat /proc/cmdline" \
  "ls /sys/firmware/efi/efivars/ | head -5" \
  "mcopy -i /dev/sda1 ::autoboot.txt -" \
  "grep 'PV_BOOTLOADER_TYPE' /storage/logs/0/pantavisor/pantavisor.log | grep config | head -1"
```

### Verify

```
# cmdline
root=/dev/sda4 ro console=ttyS0,115200 PV_BOOTLOADER_TYPE=efiab PV_LOG_SERVER_OUTPUTS=filetree

# efivarfs mounted (EFI variables accessible)
Boot0000-8be4df61-93ca-11d2-aa0d-00e098032b8c
BootCurrent-8be4df61-...
...

# autoboot.txt on ESP (A/B partition config)
[all]
tryboot_a_b=1
boot_partition=2

[tryboot]
boot_partition=3

# bootloader type recognized
PV_BOOTLOADER_TYPE = 'efiab' (env)
```

### Expected Results

| Check | Expected |
|-------|----------|
| `PV_BOOTLOADER_TYPE` | `efiab` (not `uboot`) |
| efivarfs | Mounted, standard EFI vars visible |
| autoboot.txt | Present on ESP (`/dev/sda1`), `boot_partition=2` |
| `pv_rev.txt` on boot_a | Not found (expected for factory boot) |

---

## Test 3: Container Status

**Purpose**: Verify containers start and are reachable via pvcontrol and lxc-ls.

### Execute

```bash
expect scripts/qemu-diag.exp \
  "lxc-ls -f" \
  "pvcontrol ls"
```

### Verify

```
# lxc-ls -f
NAME    STATE   AUTOSTART GROUPS IPV4                IPV6                    UNPRIVILEGED
os      RUNNING 0         -      10.0.2.15, 10.0.3.1 fec0::5054:ff:fe12:3456 false
pvr-sdk RUNNING 0         -      10.0.2.15, 10.0.3.1 fec0::5054:ff:fe12:3456 false

# pvcontrol ls
[{"name":"os","group":"root","status":"STARTED",...},
 {"name":"pvr-sdk","group":"platform","status":"STARTED",...}]
```

### Expected Results

| Check | Expected |
|-------|----------|
| `os` container | RUNNING, group `root` |
| `pvr-sdk` container | RUNNING, group `platform` |
| `pvcontrol ls` | Both containers STARTED |
| IPv4 addresses | Assigned (10.0.x.x) |

---

## Test 4: Container Shell (pventer)

**Purpose**: Verify pventer can execute commands inside running containers.

### Execute

```bash
expect scripts/qemu-diag.exp \
  "pventer -c os cat /etc/os-release 2>&1 | head -3" \
  "pventer -c os id 2>&1" \
  "pventer -c pvr-sdk id 2>&1"
```

### Verify

```
# pventer -c os cat /etc/os-release
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.17.10

# pventer -c os id
uid=0(root) gid=0(root)

# pventer -c pvr-sdk id
uid=0(root) gid=0(root)
```

### Expected Results

| Check | Expected |
|-------|----------|
| `pventer -c os` | Enters os container, can run commands |
| `pventer -c pvr-sdk` | Enters pvr-sdk container, can run commands |
| OS in `os` container | Alpine Linux |
| No illegal instruction crashes | Console clean (requires `-cpu IvyBridge` in QEMU) |

---

## Test 5: pvcontrol Operations

**Purpose**: Verify pvcontrol subcommands work (config, buildinfo, devmeta).

### Execute

```bash
expect scripts/qemu-diag.exp \
  "pvcontrol buildinfo" \
  "pvcontrol conf ls 2>&1 | head -5" \
  "pvcontrol devmeta ls 2>&1 | head -3"
```

### Verify

```
# pvcontrol buildinfo
Build Configuration:
DISTRO = panta
DISTRO_VERSION = 021

# pvcontrol conf ls (JSON array of config entries)
[{"key":"PH_CREDS_HOST","value":"api.pantahub.com",...},
 {"key":"PV_BOOTLOADER_TYPE","value":"efiab","modified":"env"},...

# pvcontrol devmeta ls
{"pantavisor.status":"READY",...}
```

### Expected Results

| Check | Expected |
|-------|----------|
| `pvcontrol buildinfo` | Shows distro name and version |
| `pvcontrol conf ls` | JSON config, PV_BOOTLOADER_TYPE=efiab |
| `pvcontrol devmeta ls` | pantavisor.status = READY |

---

## Quick Reference

### Interactive QEMU Session

```bash
# Boot interactively (Ctrl-A X to quit)
./scripts/run-qemu-efi.sh

# Press ENTER during "Press [ENTER] for debug ash shell..." countdown
# Then run any commands at the # prompt
```

### Automated Diagnostics

```bash
# Run any combination of commands
expect scripts/qemu-diag.exp "cmd1" "cmd2" "cmd3"

# Full health check
expect scripts/qemu-diag.exp \
  "lxc-ls -f" \
  "pvcontrol ls" \
  "grep -c ERROR /storage/logs/0/pantavisor/pantavisor.log" \
  "mcopy -i /dev/sda1 ::autoboot.txt -" \
  "pventer -c os id 2>&1"
```

### Key Paths (inside debug shell)

| Path | Description |
|------|-------------|
| `/storage/logs/0/pantavisor/pantavisor.log` | Pantavisor log |
| `/storage/logs/0/<container>/lxc/console.log` | Container console log |
| `/pv/pv-ctrl` | Pantavisor control socket |
| `/sys/firmware/efi/efivars/` | EFI variables (efivarfs) |
| `/dev/sda1` | ESP partition (autoboot.txt) |
| `/dev/sda2` | boot_a partition |
| `/dev/sda3` | boot_b partition |
| `/dev/sda4` | pvdata partition (root/storage) |

---

## Known Issues

| Issue | Description | Workaround |
|-------|-------------|------------|
| QEMU `-cpu` required | Default QEMU CPU (`qemu64`) lacks SSE4.1/4.2 instructions needed by Alpine container binaries, causing "Illegal instruction" crashes | Always use `-cpu IvyBridge` (already set in scripts) |
| `mcopy: File "::pv_rev.txt" not found` | Expected on factory boot — pv_rev.txt is written after first A/B update | Informational, not an error |
| `cgroup: Unknown subsys name 'hugetlb'` | Harmless cgroup v1/v2 mismatch in QEMU | Ignore |

## GPT Partition Layout

| # | Name   | Size  | Type            | Contents                            |
|---|--------|-------|-----------------|-------------------------------------|
| 1 | esp    | 64M   | EFI System      | EFI/BOOT/BOOTX64.EFI, autoboot.txt |
| 2 | boot_a | 128M  | Microsoft basic | pvboot.efi, pv-linux.efi            |
| 3 | boot_b | 128M  | Microsoft basic | pvboot.efi, pv-linux.efi (copy)     |
| 4 | (root) | ~2.6G | Linux fs (ext4) | Pantavisor state, containers        |
