SUMMARY = "A FAT32 image containing multiple kernel binaries (mcdepends)"
DESCRIPTION = "An image that automatically builds and includes kernels from multi1, multi2, and multi3 multiconfig builds."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit image

IMAGE_CLASSES:remove = "sdcard_image-rpi"

# Set the filesystem type to vfat (FAT32)
IMAGE_FSTYPES = "vfat"
IMAGE_ROOTFS_SIZE = "131072"
IMAGE_OVERHEAD_FACTOR = "1.0"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
EXTRA_IMAGECMD:vfat = "-F 32 -S 512 -n PVBOOT"

# No packages
IMAGE_INSTALL = ""
PACKAGE_INSTALL = ""
IMAGE_LINGUAS = ""

# Skip package management entirely
do_rootfs[recrdeptask] = ""

do_rootfs[depends] += "rpi-bootfiles:do_deploy"
do_rootfs[depends] += "linux-raspberrypi:do_deploy"
do_rootfs[depends] += "pantavisor-initramfs:do_image_complete"

# Declare mcdepends for the do_rootfs task.
do_rootfs[mcdepends] += "${@'rpi-kernel' in d.getVar('BBMULTICONFIG', True, '').split() and ' mc::rpi-kernel:linux-raspberrypi:do_deploy' or ''}"
do_rootfs[mcdepends] += "${@'rpi-kernel7' in d.getVar('BBMULTICONFIG', True, '').split() and ' mc::rpi-kernel7:linux-raspberrypi:do_deploy' or ''}"
do_rootfs[mcdepends] += "${@'rpi-kernel7l' in d.getVar('BBMULTICONFIG', True, '').split() and ' mc::rpi-kernel7l:linux-raspberrypi:do_deploy' or ''}"
do_rootfs[mcdepends] += "${@'rpi-kernel8' in d.getVar('BBMULTICONFIG', True, '').split() and ' mc::rpi-kernel8:linux-raspberrypi:do_deploy' or ''}"
do_rootfs[mcdepends] += "${@'rpi-kernel_2712' in d.getVar('BBMULTICONFIG', True, '').split() and ' mc::rpi-kernel_2712:linux-raspberrypi:do_deploy' or ''}"

MULTI_MACHINES = "raspberrypi raspberrypi-armv7 raspberrypi-armv8 raspberrypi2 raspberrypi5"

# Multiconfig deploy directory pattern
MC_DEPLOY_BASE = "${TOPDIR}/tmp-${DISTRO_CODENAME}-rpi-kernel"

do_rootfs() {
    rm -rf ${IMAGE_ROOTFS}
    mkdir -p ${IMAGE_ROOTFS}

    for machine in ${MULTI_MACHINES}; do
        # Try multiconfig deploy dir first, fall back to default
        machdir="${MC_DEPLOY_BASE}-$machine/deploy/images/$machine"
        [ -d "$machdir" ] || machdir="${DEPLOY_DIR}/images/$machine"
        [ -d "$machdir" ] || continue

        # Firmware (bootcode.bin, start*.elf, fixup*.dat) - exclude stamp files
        # Check multiconfig deploy dir first, then fall back to default deploy dir
        for fwdir in "$machdir/${BOOTFILES_DIR_NAME}" "${DEPLOY_DIR}/images/$machine/${BOOTFILES_DIR_NAME}"; do
            [ -d "$fwdir" ] || continue
            for f in "$fwdir"/*; do
                [ -e "$f" ] || continue
                case "$(basename $f)" in
                    *.stamp) continue ;;
                esac
                # Only copy if not already present
                [ -e "${IMAGE_ROOTFS}/$(basename $f)" ] || cp -rf "$f" ${IMAGE_ROOTFS}/
            done
        done

        # DTBs - only copy base DTB names, skip versioned and machine-suffixed files
        for f in "$machdir"/*.dtb; do
            [ -e "$f" ] || continue
            bn="$(basename $f)"
            case "$bn" in
                *-20[0-9][0-9]*.dtb) continue ;;  # skip timestamp versions
                *-raspberrypi*.dtb) continue ;;   # skip machine-suffixed duplicates
            esac
            # Only install if not already present
            [ -e "${IMAGE_ROOTFS}/$bn" ] || install -m 0644 "$f" ${IMAGE_ROOTFS}/
        done

        # Overlays - check overlays/ subdirectory and also dtbo files directly in deploy dir
        for overlaydir in "$machdir/overlays" "${DEPLOY_DIR}/images/$machine/overlays" "$machdir" "${DEPLOY_DIR}/images/$machine"; do
            [ -d "$overlaydir" ] || continue
            for f in "$overlaydir"/*.dtbo; do
                [ -e "$f" ] || continue
                bn="$(basename $f)"
                case "$bn" in
                    *-20[0-9][0-9]*.dtbo) continue ;;  # skip timestamp versions
                    *-raspberrypi*.dtbo) continue ;;   # skip machine-suffixed duplicates
                esac
                # Only install if not already present
                mkdir -p ${IMAGE_ROOTFS}/overlays
                [ -e "${IMAGE_ROOTFS}/overlays/$bn" ] || install -m 0644 "$f" ${IMAGE_ROOTFS}/overlays/
            done
            # README if present in overlays subdir
            [ -e "$overlaydir/README" ] && [ ! -e "${IMAGE_ROOTFS}/overlays/README" ] && install -m 0644 "$overlaydir/README" ${IMAGE_ROOTFS}/overlays/
        done
    done

    # Kernels - rename to RPi bootloader expected names
    # Check multiconfig deploy dirs first, then fall back to default

    # Pi 0/1: kernel.img (zImage for direct boot)
    mc_dir="${MC_DEPLOY_BASE}-raspberrypi/deploy/images/raspberrypi"
    if [ -e "$mc_dir/zImage" ]; then
        install -m 0644 "$mc_dir/zImage" ${IMAGE_ROOTFS}/kernel.img
    elif [ -e "${DEPLOY_DIR}/images/raspberrypi/zImage" ]; then
        install -m 0644 "${DEPLOY_DIR}/images/raspberrypi/zImage" ${IMAGE_ROOTFS}/kernel.img
    fi

    # Pi 2/3 32-bit: kernel7.img (zImage for direct boot)
    mc_dir="${MC_DEPLOY_BASE}-raspberrypi2/deploy/images/raspberrypi2"
    if [ -e "$mc_dir/zImage" ]; then
        install -m 0644 "$mc_dir/zImage" ${IMAGE_ROOTFS}/kernel7.img
    elif [ -e "${DEPLOY_DIR}/images/raspberrypi2/zImage" ]; then
        install -m 0644 "${DEPLOY_DIR}/images/raspberrypi2/zImage" ${IMAGE_ROOTFS}/kernel7.img
    fi

    # Pi 4 32-bit: kernel7l.img (zImage for direct boot)
    mc_dir="${MC_DEPLOY_BASE}-raspberrypi-armv7/deploy/images/raspberrypi-armv7"
    if [ -e "$mc_dir/zImage" ]; then
        install -m 0644 "$mc_dir/zImage" ${IMAGE_ROOTFS}/kernel7l.img
    elif [ -e "${DEPLOY_DIR}/images/raspberrypi-armv7/zImage" ]; then
        install -m 0644 "${DEPLOY_DIR}/images/raspberrypi-armv7/zImage" ${IMAGE_ROOTFS}/kernel7l.img
    fi

    # Pi 3/4 64-bit: kernel8.img
    mc_dir="${MC_DEPLOY_BASE}-raspberrypi-armv8/deploy/images/raspberrypi-armv8"
    if [ -e "$mc_dir/Image" ]; then
        install -m 0644 "$mc_dir/Image" ${IMAGE_ROOTFS}/kernel8.img
    elif [ -e "${DEPLOY_DIR}/images/raspberrypi-armv8/Image" ]; then
        install -m 0644 "${DEPLOY_DIR}/images/raspberrypi-armv8/Image" ${IMAGE_ROOTFS}/kernel8.img
    fi

    # Pi 5: kernel_2712.img
    mc_dir="${MC_DEPLOY_BASE}-raspberrypi5/deploy/images/raspberrypi5"
    if [ -e "$mc_dir/Image" ]; then
        install -m 0644 "$mc_dir/Image" ${IMAGE_ROOTFS}/kernel_2712.img
    elif [ -e "${DEPLOY_DIR}/images/raspberrypi5/Image" ]; then
        install -m 0644 "${DEPLOY_DIR}/images/raspberrypi5/Image" ${IMAGE_ROOTFS}/kernel_2712.img
    fi

    # Initramfs
    if [ -e "${DEPLOY_DIR_IMAGE}/pantavisor-initramfs-${MACHINE}.cpio.gz" ]; then
        install -m 0644 "${DEPLOY_DIR_IMAGE}/pantavisor-initramfs-${MACHINE}.cpio.gz" ${IMAGE_ROOTFS}/pantavisor
    fi

    # config.txt for kernel/initramfs selection
    cat > ${IMAGE_ROOTFS}/config.txt << 'EOF'
# Pantavisor RPi tryboot config
# Auto-generated - do not edit

[all]
disable_splash=1
boot_delay=0
initramfs pantavisor followkernel

# kernel selection based on Pi model
[pi0]
kernel=kernel.img

[pi0w]
kernel=kernel.img

[pi02]
kernel=kernel8.img

[pi1]
kernel=kernel.img

[pi2]
kernel=kernel7.img

[pi3]
kernel=kernel8.img

[pi3+]
kernel=kernel8.img

[pi4]
kernel=kernel8.img

[cm4]
kernel=kernel8.img

[pi400]
kernel=kernel8.img

[pi5]
kernel=kernel_2712.img

[cm5]
kernel=kernel_2712.img

[all]
# Enable UART for debugging
enable_uart=1
# Enable hardware watchdog for shutdown safety
dtparam=watchdog=on
EOF

    # cmdline.txt for kernel command line
    local cmdline="console=serial0,115200 panic=5 PV_BOOTLOADER_TYPE=rpiab PV_SYSTEM_DRIVERS_AUTO=hotplug"
    if ${@bb.utils.contains('PANTAVISOR_FEATURES', 'console-logging', 'true', 'false', d)}; then
        cmdline="$cmdline PV_LOG_SERVER_OUTPUTS=stdout,filetree ignore_loglevel printk.devkmsg=on"
    fi
    echo "$cmdline" > ${IMAGE_ROOTFS}/cmdline.txt
}

create_wks_symlink() {
    ln -sf ${IMAGE_NAME}.rootfs.vfat ${DEPLOY_DIR_IMAGE}/${PN}-${MACHINE}.vfat
}

do_image_complete[postfuncs] += "create_wks_symlink"


