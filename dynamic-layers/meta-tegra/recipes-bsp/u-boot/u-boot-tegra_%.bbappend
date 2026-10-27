FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# u-boot%.bbappend also matches u-boot-tegra; replace its generic script
# with one which preserves the DTB passed by NVIDIA's CBoot firmware.
uboot_env_src_frags:mc-default:jetson-nano-devkit = "boot.cmd.jetson-nano"
SRC_URI:append:jetson-nano-devkit = " file://boot.cmd.jetson-nano file://pv.jetson-nano.cfg"
