#!/bin/bash
# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT
#
# Run pantavisor-remix WIC image in QEMU with OVMF firmware.
# Uses Yocto-built qemu-system-native and OVMF from the build output.
#
# Usage: ./scripts/run-qemu-efi.sh [--timeout SECONDS]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILDDIR="$TOP_DIR/build"
TMPDIR="$BUILDDIR/tmp-scarthgap"
DEPLOY="$TMPDIR/deploy/images/x64-efi"
NATIVE_BASE="$TMPDIR/sysroots-components/x86_64"
UNINATIVE="$TMPDIR/sysroots-uninative/x86_64-linux"

QEMU="$NATIVE_BASE/qemu-system-native/usr/bin/qemu-system-x86_64"
LOADER="$UNINATIVE/lib/ld-linux-x86-64.so.2"
QEMU_DATA="$NATIVE_BASE/qemu-system-native/usr/share/qemu"

WIC="$DEPLOY/pantavisor-remix-x64-efi.rootfs.wic"
OVMF_CODE="$DEPLOY/ovmf.code.qcow2"
OVMF_VARS="$DEPLOY/ovmf.vars.qcow2"

TIMEOUT=""
EXTRA_ARGS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# Verify prerequisites
for f in "$QEMU" "$LOADER" "$WIC" "$OVMF_CODE" "$OVMF_VARS"; do
    if [ ! -e "$f" ]; then
        echo "ERROR: missing $f" >&2
        echo "Build first: ./kas-container build .github/configs/release/x64-efi-scarthgap.yaml" >&2
        exit 1
    fi
done

# Build LD_LIBRARY_PATH from uninative + native sysroot components
LIB_PATH="$UNINATIVE/lib:$UNINATIVE/usr/lib"
for d in "$NATIVE_BASE"/*/usr/lib; do
    [ -d "$d" ] && LIB_PATH="$LIB_PATH:$d"
done
# Writable copy of OVMF vars (UEFI needs to write NV variables)
VARS_COPY=$(mktemp /tmp/ovmf-vars-XXXXXX.qcow2)
cp -f "$OVMF_VARS" "$VARS_COPY"
trap "rm -f $VARS_COPY" EXIT

SERIAL_LOG=/tmp/qemu-serial.log

echo "=== QEMU EFI boot ==="
echo "WIC:  $WIC"
echo "OVMF: $OVMF_CODE"
echo "Serial log: $SERIAL_LOG"
echo ""

rm -f "$SERIAL_LOG"

# Run QEMU via uninative loader (LD_LIBRARY_PATH must NOT leak to host tools)
QEMU_CMD=(
    "$LOADER" --library-path "$LIB_PATH" "$QEMU"
    -L "$QEMU_DATA"
    -machine q35
    -cpu IvyBridge
    -m 2048
    -smp 2
    -nographic
    -drive "if=pflash,format=qcow2,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=qcow2,file=$VARS_COPY"
    -drive "format=raw,file=$WIC"
    -netdev user,id=net0 -device e1000,netdev=net0
    -serial mon:stdio
    $EXTRA_ARGS
)

if [ -n "$TIMEOUT" ]; then
    timeout "$TIMEOUT" "${QEMU_CMD[@]}" || true
else
    "${QEMU_CMD[@]}"
fi
