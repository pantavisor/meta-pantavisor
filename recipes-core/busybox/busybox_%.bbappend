# devmem applet: physical-memory peek/poke from the initramfs debug shell —
# essential for register-level bring-up work on BSP targets (added for the
# Orange Pi i96 WiFi bring-up; harmless and useful everywhere else).
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://devmem.cfg"
