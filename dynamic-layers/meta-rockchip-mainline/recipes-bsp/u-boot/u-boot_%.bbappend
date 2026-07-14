FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Enable U-Boot BOOTSTD/bootflow with the distro bootmeths (script + extlinux).
# The "script" bootmeth is what lets `bootflow scan` find and source our
# boot.scr, so Pantavisor's boot logic still runs.
SRC_URI += "file://pv-bootstd.cfg"

# Mainline rockchip U-Boot uses BOOTSTD/bootflow and has no legacy
# "distro_bootcmd" environment, so the generic pv.distroboot.cfg override
# (CONFIG_BOOTCOMMAND="run distro_bootcmd") from recipes-bsp/u-boot would leave
# the board unable to autoboot. Drop it here and let the board's native BOOTSTD
# default (CONFIG_BOOTCOMMAND="bootflow scan") run instead.
SRC_URI:remove = "file://pv.distroboot.cfg"

# Define a custom task to stitch the rksd_loader image
do_compile:append() {
    if [ -f "${B}/idbloader.img" ] && [ -f "${B}/u-boot.itb" ]; then
        bbnote "Creating custom rksd_loader.img for legacy DOS systems..."
        
        # 1. Initialize a blank 12MB file with zeros
        dd if=/dev/zero of=${B}/rksd_loader.img bs=1M count=12
        
        # 2. Inject idbloader.img at Sector 64
        dd if=${B}/idbloader.img of=${B}/rksd_loader.img bs=512 seek=64 conv=notrunc
        
        # 3. Inject u-boot.itb at Sector 16384
        dd if=${B}/u-boot.itb of=${B}/rksd_loader.img bs=512 seek=16384 conv=notrunc
    else
        bbfatal "Required U-Boot build artifacts for rksd_loader.img missing!"
    fi
}

# Tell Yocto to deploy the stitched image alongside standard U-Boot binaries
do_deploy:append() {
    if [ -f "${B}/rksd_loader.img" ]; then
        install -m 0644 ${B}/rksd_loader.img ${DEPLOYDIR}/rksd_loader-${PV}-${PR}.img
        ln -sf rksd_loader-${PV}-${PR}.img ${DEPLOYDIR}/rksd_loader.img
    fi
}

