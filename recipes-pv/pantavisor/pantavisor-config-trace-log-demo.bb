SUMMARY = "pantavisor.config overlay setting PV_LOG_LEVEL to TRACE"
DESCRIPTION = "\
Showcase consumer of pantavisor-config-provider.bbclass: takes the \
upstream-rendered /etc/pantavisor.config from sysroot and raises \
PV_LOG_LEVEL to TRACE (5) for verbose debugging. Select via \
  VIRTUAL-RUNTIME_pantavisor_config = \"pantavisor-config-trace-log-demo\" \
in a distro or image."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pantavisor-config-provider

PV_CONFIG_SET = "PV_LOG_LEVEL=5"
