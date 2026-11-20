#!/bin/bash
# Boot a dgx-spark disk image in QEMU through the same chain as the hardware:
# UEFI (AAVMF, Secure Boot off) -> systemd-boot -> UKI -> pantavisor, with the
# image on an emulated NVMe. Needs qemu-system-arm and qemu-efi-aarch64.
#
# The UKI cmdline is fixed at build time, so build with the serial console
# overlay or the console stays on the (absent) screen:
#
#   ./kas-container build kas/build-configs/release/nvidia-dgx-spark-scarthgap.yaml:kas/with-serial-console.yaml
#
# The disk and the EFI variable store are copies under build/qemu-dgx-spark/
# and survive between runs, like a real device; --fresh starts over from the
# deployed image. The variable store matters for systemd-boot's
# LoaderEntryOneShot/LoaderEntryDefault.
#
# Usage: scripts/run-qemu-dgx-spark.sh [--fresh] [--disk-size SIZE] [--ssh-port PORT] [image.wic]
# Quit with Ctrl-A X.

set -euo pipefail

TOP="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY="$TOP/build/tmp-scarthgap/deploy/images/dgx-spark"
STATE="$TOP/build/qemu-dgx-spark"
AAVMF_CODE="${AAVMF_CODE:-/usr/share/AAVMF/AAVMF_CODE.no-secboot.fd}"
AAVMF_VARS="${AAVMF_VARS:-/usr/share/AAVMF/AAVMF_VARS.fd}"

fresh=0
# Room for autogrow to resize the root partition on first boot.
disk_size=16G
ssh_port=8222
image=""

while [ $# -gt 0 ]; do
	case "$1" in
	--fresh) fresh=1 ;;
	--disk-size) disk_size="$2"; shift ;;
	--ssh-port) ssh_port="$2"; shift ;;
	-h|--help) sed -n '2,20s/^# \{0,1\}//p' "$0"; exit 0 ;;
	-*) echo "unknown option: $1" >&2; exit 2 ;;
	*) image="$1" ;;
	esac
	shift
done

image="${image:-$DEPLOY/pantavisor-starter-dgx-spark.rootfs.wic}"
for f in "$image" "$AAVMF_CODE" "$AAVMF_VARS"; do
	[ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
command -v qemu-system-aarch64 >/dev/null || { echo "qemu-system-aarch64 not found" >&2; exit 1; }

mkdir -p "$STATE"
if [ "$fresh" = 1 ] || [ ! -f "$STATE/disk.img" ]; then
	cp --sparse=always "$image" "$STATE/disk.img"
	truncate -s "$disk_size" "$STATE/disk.img"
	cp "$AAVMF_VARS" "$STATE/vars.fd"
	echo "fresh disk ($disk_size) and EFI variables from $image"
fi

# No KVM for aarch64 on an x86 host: TCG. pauth-impdef keeps pointer
# authentication from dominating emulation time.
exec qemu-system-aarch64 \
	-machine virt,gic-version=3 \
	-cpu max,pauth-impdef=on \
	-smp 4 \
	-m 4096 \
	-drive if=pflash,format=raw,readonly=on,file="$AAVMF_CODE" \
	-drive if=pflash,format=raw,file="$STATE/vars.fd" \
	-drive id=nvme0,if=none,format=raw,file="$STATE/disk.img" \
	-device nvme,serial=pvdgxspark0,drive=nvme0 \
	-netdev user,id=net0,hostfwd=tcp::"$ssh_port"-:8222 \
	-device virtio-net-pci,netdev=net0 \
	-device virtio-rng-pci \
	-nographic
