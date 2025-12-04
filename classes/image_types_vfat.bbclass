# Backport vfat image type from Scarthgap for Kirkstone compatibility
# This becomes a no-op on Scarthgap+ where vfat is already in IMAGE_TYPES

def vfat_already_supported(d):
    return 'vfat' in d.getVar('IMAGE_TYPES').split()

# Only add if not already present (Kirkstone)
python () {
    if not vfat_already_supported(d):
        d.appendVar('IMAGE_TYPES', ' vfat')
}

# Note that vfat can't handle all types of files that a real linux file system
# can (e.g. device files, symlinks, etc.) and therefore is not suitable for all
# use cases
oe_mkvfatfs () {
    mkfs.vfat $@ -C ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.vfat ${ROOTFS_SIZE}
    mcopy -i "${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.vfat" -vsmpQ ${IMAGE_ROOTFS}/* ::/
}

IMAGE_CMD:vfat = "oe_mkvfatfs ${EXTRA_IMAGECMD}"

# If a specific FAT size is needed, set it here (e.g. "-F 32"/"-F 16"/"-F 12")
# otherwise mkfs.vfat will automatically pick one.
EXTRA_IMAGECMD:vfat ?= ""

do_image_vfat[depends] += "dosfstools-native:do_populate_sysroot mtools-native:do_populate_sysroot"

