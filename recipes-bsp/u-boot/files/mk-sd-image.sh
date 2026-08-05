#!/bin/sh
# Assemble a flashable OrangePi i96 (RDA8810PL) SD image by hand from the deploy
# artifacts + the hybrid bootloader. This is the "direct-boot" form (static kernel
# on the boot partition); the full pantavisor FIT/rollback boot is the Yocto wic
# path (see wic/orangepi-i96.wks + M4-switchover.md in the meta-orangepi-i96
# layer, github.com/pantavisor/meta-orangepi-i96). Both flash the same layout.
#
# Layout (matches the vendor SD): gap[bootloader@0x20000] + ext boot p1(64M @2M) +
# ext4 rootfs p2. Needs: mke2fs (-d), sfdisk, u-boot mkimage.
set -eu
DEPLOY="${DEPLOY:?set DEPLOY=.../deploy/images/orangepi-i96}"
# No .rda is kept in the tree: they are build artifacts that go stale silently.
# A blob predating the five-register AP pad map (MODEM-WIFI-PORT.md section 15,
# in the meta-orangepi-i96 layer)
# boots normally but leaves no SDIO and no wlan0, which reads as a driver
# regression. Verify before use -- all five must be present as LE u32:
#   0x7fe0003f 0x000210fc 0x3f00033f 0x14040040 0x006e4524
# A known-good blob can be lifted from a working image:
#   dd if=<working>.img of=bootloader.rda bs=512 skip=256 count=3840
BL="${BL:?set BL=path to the RDA8810 bootloader blob (SPL + stage-2 u-boot)}"
MKIMAGE="${MKIMAGE:-mkimage}"
OUT="${OUT:-orangepi-i96-pantavisor.img}"
W="$(mktemp -d)"; mkdir -p "$W/boot"

cp "$DEPLOY/zImage" "$W/boot/zImage"
cp "$DEPLOY/rda8810pl-orangepi-i96.dtb" "$W/boot/rda8810pl-orangepi-i96.dtb"
"$MKIMAGE" -A arm -O linux -T ramdisk -C gzip -a 0x85000000 -e 0x85000000 -n pv-initramfs \
	-d "$DEPLOY/pantavisor-initramfs-orangepi-i96.cpio.gz" "$W/boot/uInitrd"
cat > "$W/boot.cmd" <<'EOF'
# pantavisor convention: console/baudrate/fdtfile/*_addr_r come from the board
# u-boot default env (include/configs/rda8810pl.h). console=ttyRDA2 there — the
# mainline rda-uart driver, NOT ttyS*. earlycon uses the DT stdout-path.
setenv bootargs "earlycon console=${console},${baudrate} root=/dev/ram rootfstype=ramfs rdinit=/usr/bin/pantavisor pv_storage.device=/dev/mmcblk0p2 pv_storage.fstype=ext4 panic=3"
# Per-board WiFi MAC. The RDA5991 has no MAC storage, so without this the
# driver picks a fresh random address every boot, which orphans ConnMan's
# saved services. It must reach the driver itself (rdawfmac.mac_addr=):
# setting the address from userspace afterwards is racy, because the driver
# re-applies its own when the interface is opened.
# Only needed to PIN an address to a board. Without one the driver derives a
# stable MAC from the boot card's CID, so a fresh board needs no provisioning.
# Set WLANMAC=<addr> when running this script to bake it in, or add a line
# "wlanmac=02:53:79:78:01:5b" to wlanmac.txt on this partition by hand.
if load mmc 0:1 ${loadaddr} wlanmac.txt; then
	env import -t ${loadaddr} ${filesize}
	if test -n "${wlanmac}"; then
		setenv bootargs "${bootargs} rdawfmac.mac_addr=${wlanmac}"
	fi
fi
load mmc 0:1 ${kernel_addr_r} zImage
load mmc 0:1 ${fdt_addr_r} ${fdtfile}
load mmc 0:1 ${ramdisk_addr_r} uInitrd
bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
EOF
"$MKIMAGE" -A arm -O linux -T script -C none -n "pv boot" -d "$W/boot.cmd" "$W/boot/boot.scr"

# Bake in a pinned station MAC when given. Optional: the driver derives one
# from the boot card's CID by itself. Use this only to tie an address to a
# board rather than to a card.
if [ -n "${WLANMAC:-}" ]; then
	echo "wlanmac=$WLANMAC" > "$W/boot/wlanmac.txt"
	echo "baked wlanmac=$WLANMAC into the boot partition"
fi

mke2fs -q -t ext4 -L boot -d "$W/boot" -F "$W/boot.ext4" 64M
gzip -dc "$DEPLOY"/pantavisor-starter-orangepi-i96.rootfs.ext4.gz > "$W/rootfs.ext4"

rootsec=$(( $(stat -c%s "$W/rootfs.ext4") / 512 ))
total=$(( 135168 + rootsec ))
truncate -s $((total * 512)) "$OUT"
printf 'label: dos\nunit: sectors\nstart=4096, size=131072, type=83\nstart=135168, size=%s, type=83\n' "$rootsec" | sfdisk -q "$OUT"
dd if="$BL"            of="$OUT" bs=512 seek=256    conv=notrunc status=none  # bootloader @0x20000
dd if="$W/boot.ext4"  of="$OUT" bs=512 seek=4096   conv=notrunc status=none  # p1 boot
dd if="$W/rootfs.ext4" of="$OUT" bs=512 seek=135168 conv=notrunc status=none # p2 rootfs
rm -rf "$W"
echo "SD image: $OUT  ($(stat -c%s "$OUT") bytes) — flash with dd/bmaptool, then boot serial @921600"
