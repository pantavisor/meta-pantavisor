#!/bin/bash

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

#
# test-qemu-efi.sh — Test pv-efi-boot in QEMU with OVMF
#
# Creates a GPT test disk with the Pantavisor EFI partition layout,
# populates it with built EFI binaries, and boots with QEMU + OVMF.
#
# Usage:
#   ./scripts/test-qemu-efi.sh [deploy-dir]
#
# If deploy-dir is not specified, defaults to:
#   build/tmp-scarthgap/deploy/images/qemu-x86-64-efi/
#
# Requirements:
#   - sgdisk (gdisk package)
#   - mtools (mcopy, mformat)
#   - qemu-system-x86_64
#   - Built EFI artifacts in deploy directory

set -euo pipefail

DEPLOY_DIR="${1:-build/tmp-scarthgap/deploy/images/qemu-x86-64-efi}"

# EFI binaries
STAGE1="${DEPLOY_DIR}/pvboot-stage1.efi"
STAGE2="${DEPLOY_DIR}/pvboot-stage2.efi"
AUTOBOOT="${DEPLOY_DIR}/autoboot.txt"

# UKI (optional — test proceeds without it, stage2 will fail gracefully)
UKI="${DEPLOY_DIR}/pv-linux.efi"

# OVMF firmware — check common locations
OVMF=""
for candidate in \
    "${DEPLOY_DIR}/ovmf.fd" \
    "/usr/share/OVMF/OVMF_CODE.fd" \
    "/usr/share/edk2/ovmf/OVMF_CODE.fd" \
    "/usr/share/qemu/OVMF_CODE.fd"; do
    if [ -f "$candidate" ]; then
        OVMF="$candidate"
        break
    fi
done

# Temporary working directory
WORKDIR=$(mktemp -d /tmp/pv-efi-test.XXXXXX)
trap 'rm -rf "$WORKDIR"' EXIT

DISK="${WORKDIR}/test-disk.img"
DISK_SIZE_MB=512

echo "=== pv-efi-boot QEMU test ==="
echo "Deploy dir: ${DEPLOY_DIR}"
echo "Work dir:   ${WORKDIR}"

# Validate required files
for f in "$STAGE1" "$STAGE2" "$AUTOBOOT"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: Required file not found: $f"
        echo "Build pv-efi-boot first:"
        echo "  ./kas-container build .github/configs/release/docker-x86_64-scarthgap.yaml --target pv-efi-boot"
        exit 1
    fi
done

if [ -z "$OVMF" ]; then
    echo "ERROR: OVMF firmware not found."
    echo "Install ovmf package or build it with Yocto."
    exit 1
fi

echo "OVMF: ${OVMF}"

# Step 1: Create blank disk image
echo ""
echo "--- Creating ${DISK_SIZE_MB}MB disk image ---"
dd if=/dev/zero of="$DISK" bs=1M count=${DISK_SIZE_MB} status=none

# Step 2: Create GPT partition table
echo "--- Creating GPT partitions ---"
sgdisk --clear \
    --new=1:2048:+64M    --typecode=1:EF00 --change-name=1:"esp" \
    --new=2:0:+128M      --typecode=2:0700 --change-name=2:"pvboot-a" \
    --new=3:0:+128M      --typecode=3:0700 --change-name=3:"pvboot-b" \
    --new=4:0:0          --typecode=4:8300 --change-name=4:"pvdata" \
    "$DISK"

# Step 3: Format FAT32 partitions using mtools
# Get partition offsets from sgdisk
echo "--- Formatting FAT32 partitions ---"

# Partition offsets (sectors, 512 bytes each)
ESP_START=$(sgdisk -i 1 "$DISK" | grep "First sector" | awk '{print $3}')
ESP_SIZE=$(sgdisk -i 1 "$DISK" | grep "Partition size" | awk '{print $3}')
BOOTA_START=$(sgdisk -i 2 "$DISK" | grep "First sector" | awk '{print $3}')
BOOTA_SIZE=$(sgdisk -i 2 "$DISK" | grep "Partition size" | awk '{print $3}')
BOOTB_START=$(sgdisk -i 3 "$DISK" | grep "First sector" | awk '{print $3}')
BOOTB_SIZE=$(sgdisk -i 3 "$DISK" | grep "Partition size" | awk '{print $3}')

# Format each partition with mformat
format_partition() {
    local label="$1" start="$2" size="$3"
    mformat -i "${DISK}@@$((start * 512))" -h 32 -t "$((size / 32 / 63))" -n 63 \
        -v "$label" :: 2>/dev/null || true
    # Fallback: use dd + mkfs.vfat if mformat direct offset fails
    local part_img="${WORKDIR}/${label}.img"
    dd if=/dev/zero of="$part_img" bs=512 count="$size" status=none
    mkfs.vfat -n "$label" "$part_img" >/dev/null 2>&1
    dd if="$part_img" of="$DISK" bs=512 seek="$start" count="$size" conv=notrunc status=none
    echo "$part_img"
}

ESP_IMG=$(format_partition "ESP" "$ESP_START" "$ESP_SIZE")
BOOTA_IMG=$(format_partition "PVBOOTA" "$BOOTA_START" "$BOOTA_SIZE")
BOOTB_IMG=$(format_partition "PVBOOTB" "$BOOTB_START" "$BOOTB_SIZE")

# Step 4: Populate ESP (partition 1)
echo "--- Populating ESP ---"

# Copy stage 1 as both pvboot.efi and EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP_IMG" "$STAGE1" ::/pvboot.efi
mmd -i "$ESP_IMG" ::/EFI 2>/dev/null || true
mmd -i "$ESP_IMG" ::/EFI/BOOT 2>/dev/null || true
mcopy -i "$ESP_IMG" "$STAGE1" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ESP_IMG" "$AUTOBOOT" ::/autoboot.txt

# Write ESP back to disk
dd if="$ESP_IMG" of="$DISK" bs=512 seek="$ESP_START" conv=notrunc status=none

# Step 5: Populate boot partition A (partition 2)
echo "--- Populating pvboot-a ---"
mcopy -i "$BOOTA_IMG" "$STAGE2" ::/pvboot.efi
if [ -f "$UKI" ]; then
    mcopy -i "$BOOTA_IMG" "$UKI" ::/pv-linux.efi
    echo "  UKI installed on pvboot-a"
else
    echo "  WARNING: No UKI found, stage2 will fail (testing fallback path)"
fi
dd if="$BOOTA_IMG" of="$DISK" bs=512 seek="$BOOTA_START" conv=notrunc status=none

# Step 6: Populate boot partition B (partition 3) — stage2 only, no UKI
echo "--- Populating pvboot-b ---"
mcopy -i "$BOOTB_IMG" "$STAGE2" ::/pvboot.efi
dd if="$BOOTB_IMG" of="$DISK" bs=512 seek="$BOOTB_START" conv=notrunc status=none

# Step 7: Print summary
echo ""
echo "=== Disk layout ==="
sgdisk -p "$DISK"
echo ""
echo "ESP contents:"
mdir -i "$ESP_IMG" ::
echo ""
echo "pvboot-a contents:"
mdir -i "$BOOTA_IMG" ::

# Step 8: Launch QEMU
echo ""
echo "=== Launching QEMU ==="
echo "Press Ctrl-A X to exit QEMU serial console"
echo ""

QEMU_ARGS=(
    -bios "$OVMF"
    -drive "file=$DISK,format=raw,if=ide"
    -m 1024
    -nographic
    -serial mon:stdio
    -net none
    -no-reboot
)

# Add OVMF vars if using split firmware
OVMF_VARS=""
for candidate in \
    "/usr/share/OVMF/OVMF_VARS.fd" \
    "/usr/share/edk2/ovmf/OVMF_VARS.fd" \
    "/usr/share/qemu/OVMF_VARS.fd"; do
    if [ -f "$candidate" ]; then
        OVMF_VARS="$candidate"
        break
    fi
done

if [ -n "$OVMF_VARS" ]; then
    cp "$OVMF_VARS" "${WORKDIR}/OVMF_VARS.fd"
    QEMU_ARGS=(
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF"
        -drive "if=pflash,format=raw,file=${WORKDIR}/OVMF_VARS.fd"
        -drive "file=$DISK,format=raw,if=ide"
        -m 1024
        -nographic
        -serial mon:stdio
        -net none
        -no-reboot
    )
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
