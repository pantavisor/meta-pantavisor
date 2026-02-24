# TESTPLAN: EFI A/B Boot (x64-efi)

Test plan for the pantavisor-remix EFI A/B boot image on x64-efi machine.

## Build

```bash
# Full build (with workspace pantavisor)
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml:kas/with-workspace.yaml

# Full build (upstream sources)
./kas-container build .github/configs/release/x64-efi-scarthgap.yaml
```

Build output: `build/tmp-scarthgap/deploy/images/x64-efi/pantavisor-remix-x64-efi.rootfs.wic`

## QEMU Testing

### Prerequisites

The build produces:
- `pantavisor-remix-x64-efi.rootfs.wic` — GPT disk image (ESP + boot_a + boot_b + pvdata)
- `ovmf.code.qcow2` / `ovmf.vars.qcow2` — UEFI firmware
- `qemu-system-native` — Yocto-built QEMU (no host QEMU needed)

### Quick run

```bash
# Run with 60s timeout (non-interactive, serial to stdout)
./scripts/run-qemu-efi.sh --timeout 60

# Run interactively (Ctrl-A X to quit)
./scripts/run-qemu-efi.sh
```

The script uses Yocto-built `qemu-system-native` with the uninative loader, so no host QEMU installation is required.

### Manual QEMU command

```bash
DEPLOY=build/tmp-scarthgap/deploy/images/x64-efi
NATIVE=build/tmp-scarthgap/sysroots-components/x86_64
UNINATIVE=build/tmp-scarthgap/sysroots-uninative/x86_64-linux
LOADER=$UNINATIVE/lib/ld-linux-x86-64.so.2
QEMU=$NATIVE/qemu-system-native/usr/bin/qemu-system-x86_64

# Build LD_LIBRARY_PATH
LIB_PATH="$UNINATIVE/lib:$UNINATIVE/usr/lib"
for d in $NATIVE/*/usr/lib; do [ -d "$d" ] && LIB_PATH="$LIB_PATH:$d"; done

cp $DEPLOY/ovmf.vars.qcow2 /tmp/ovmf-vars.qcow2

$LOADER --library-path "$LIB_PATH" $QEMU \
    -L $NATIVE/qemu-system-native/usr/share/qemu \
    -machine q35 -m 2048 -smp 2 -nographic \
    -drive if=pflash,format=qcow2,readonly=on,file=$DEPLOY/ovmf.code.qcow2 \
    -drive if=pflash,format=qcow2,file=/tmp/ovmf-vars.qcow2 \
    -drive format=raw,file=$DEPLOY/pantavisor-remix-x64-efi.rootfs.wic \
    -netdev user,id=net0 -device e1000,netdev=net0 \
    -serial mon:stdio
```

## EFI Boot Chain

Expected serial output:

```
BdsDxe: loading Boot0001 "UEFI QEMU HARDDISK QM00001 "
BdsDxe: starting Boot0001 "UEFI QEMU HARDDISK QM00001 "
pv-efi-boot stage1          <-- BOOTX64.EFI from ESP
Loading stage2...
pv-efi-boot stage2          <-- pvboot.efi from boot_a
Loading UKI...
Starting UKI...              <-- pv-linux.efi (kernel + initramfs)
...
Pantavisor starting...       <-- pantavisor init
```

## GPT Partition Layout

| # | Name   | Size  | Type            | Contents                          |
|---|--------|-------|-----------------|-----------------------------------|
| 1 | esp    | 64M   | EFI System      | EFI/BOOT/BOOTX64.EFI, autoboot.txt |
| 2 | boot_a | 128M  | Microsoft basic | pvboot.efi, pv-linux.efi          |
| 3 | boot_b | 128M  | Microsoft basic | pvboot.efi, pv-linux.efi (copy)   |
| 4 | (root) | ~2.6G | Linux fs (ext4) | Pantavisor state, containers      |

Verify with: `fdisk -l build/tmp-scarthgap/deploy/images/x64-efi/pantavisor-remix-x64-efi.rootfs.wic`

## Test Cases

### TC-1: EFI boot chain

**Steps:** Run QEMU, observe serial output.

**Expected:**
- [ ] OVMF finds ESP and loads `BOOTX64.EFI`
- [ ] Stage1 prints `pv-efi-boot stage1` and loads stage2
- [ ] Stage2 prints `pv-efi-boot stage2` and loads UKI
- [ ] Kernel boots (Linux version line visible)
- [ ] `Pantavisor starting...` appears

### TC-2: Pantavisor storage mount

**Steps:** Run with `PV_LOG_SERVER_OUTPUTS=stdout_direct,filetree` in cmdline.txt.

**Expected:**
- [ ] `EXT4-fs (sda4): mounted filesystem ... r/w` in kernel log
- [ ] Pantavisor banner prints (ASCII art)
- [ ] No `FATAL` mount errors

### TC-3: Pantavisor reaches STATE_WAIT

**Steps:** Run with 60s timeout.

**Expected:**
- [ ] Log shows `next state: 'STATE_INIT'`
- [ ] Log shows `next state: 'STATE_WAIT'`
- [ ] Device registers with pantahub (challenge word appears)

### TC-4: PV_BOOTLOADER_TYPE is efiab

**Steps:** Check pantavisor config output in log.

**Expected:**
- [ ] `PV_BOOTLOADER_TYPE = 'efiab'` in config printout

**Status:** FAILING — currently shows `uboot` despite cmdline having `efiab`. Needs investigation (config file override?).

### TC-5: Containers start (pv-alpine-connman, pv-pvr-sdk)

**Steps:** Run long enough for containers to start (~30-60s after STATE_WAIT).

**Expected:**
- [ ] LXC container start messages in log
- [ ] `pv-alpine-connman` and `pv-pvr-sdk` running

**Status:** Not yet tested — device stays in STATE_WAIT (unclaimed).

### TC-6: Debug shell access

**Steps:** Run interactively, press ENTER during 5s countdown.

**Expected:**
- [ ] `Press [ENTER] for debug ash shell...` prompt appears
- [ ] Pressing ENTER drops to ash shell
- [ ] Can run `lsblk`, `mount`, `cat /proc/cmdline`

## Kernel cmdline

Current (`recipes-bsp/pv-uki/files/cmdline.txt`):
```
root=/dev/sda4 ro console=ttyS0,115200 PV_BOOTLOADER_TYPE=efiab PV_LOG_SERVER_OUTPUTS=stdout_direct,filetree
```

| Parameter | Purpose |
|-----------|---------|
| `root=/dev/sda4` | Root partition (pvdata) |
| `console=ttyS0,115200` | Serial console for QEMU |
| `PV_BOOTLOADER_TYPE=efiab` | EFI A/B boot scheme |
| `PV_LOG_SERVER_OUTPUTS=stdout_direct,filetree` | Verbose pantavisor logging |

For production, remove `PV_LOG_SERVER_OUTPUTS` and add `quiet`.

## Known Issues

1. **PV_BOOTLOADER_TYPE shows uboot**: Despite cmdline having `efiab`, pantavisor config shows `uboot (env)`. A config file in the initramfs or rootfs may be overriding the cmdline value.

2. **cgroup warnings**: `Could not mount cpu/hugetlb/net_cls/net_prio cgroup` — harmless in QEMU, kernel cgroup v1/v2 mismatch.

## Key Files

| File | Purpose |
|------|---------|
| `wic/pantavisor-efi.wks` | GPT partition layout |
| `recipes-bsp/pv-efi-boot/efi-esp-image.bb` | ESP partition image |
| `recipes-bsp/pv-efi-boot/efi-boot-image.bb` | Boot partition image (A/B) |
| `recipes-bsp/pv-uki/pv-uki_1.0.bb` | Unified Kernel Image |
| `recipes-bsp/pv-uki/files/cmdline.txt` | Kernel command line |
| `conf/machine/x64-efi.conf` | Machine configuration |
| `.github/configs/release/x64-efi-scarthgap.yaml` | KAS build config |
| `scripts/run-qemu-efi.sh` | QEMU convenience script |
