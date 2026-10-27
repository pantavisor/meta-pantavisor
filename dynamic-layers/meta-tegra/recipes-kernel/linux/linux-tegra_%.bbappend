FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:tegra210 = " file://tegra-no-se-crypto.cfg"
