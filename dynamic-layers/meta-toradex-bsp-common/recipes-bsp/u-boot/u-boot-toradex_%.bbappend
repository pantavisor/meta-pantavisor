OVERRIDES =. "mc-${BB_CURRENT_MC}:"

# pv.distroboot.cfg forces CONFIG_BOOTCOMMAND="run distro_bootcmd", which
# overrides the "fastboot usb 0" bootcmd set by u-boot-toradex-tezi.inc for
# the tezi-recovery multiconfig. Exclude it from the recovery build so the
# recovery U-Boot auto-enters fastboot mode after SDP boot.
SRC_URI:remove:mc-tezi-recovery = "file://pv.distroboot.cfg"
