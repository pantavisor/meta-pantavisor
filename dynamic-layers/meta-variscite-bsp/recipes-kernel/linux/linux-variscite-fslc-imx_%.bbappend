FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://tailscale.cfg"
SRC_URI += "file://0001-arm64-dts-imx8mn-var-som-m7-use-mmio-method-for-remo.patch"
