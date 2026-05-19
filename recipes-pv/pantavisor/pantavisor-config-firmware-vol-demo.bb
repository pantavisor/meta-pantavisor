SUMMARY = "pantavisor.config overlay enabling PV_STORAGE_FIRMWARE_VOL"
DESCRIPTION = "\
Showcase consumer of pantavisor-config-provider.bbclass: takes the \
upstream-rendered /etc/pantavisor.config from sysroot and flips on \
PV_STORAGE_FIRMWARE_VOL so a pv--firmware bsp volume becomes the kernel \
firmware_class search path. Select via \
  VIRTUAL-RUNTIME_pantavisor_config = \"pantavisor-config-firmware-vol-demo\" \
in a distro or image."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pantavisor-config-provider

PV_CONFIG_SET = "PV_STORAGE_FIRMWARE_VOL=1"
