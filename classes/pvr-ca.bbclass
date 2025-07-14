
PVS_VENDOR_NAME ??= "generic"
PVS_URI ??= "https://gitlab.com/pantacor/pv-developer-ca/-/archive/2340d747c4acd0a1a702b3d7d5acc014b51daaa7/pv-developer-ca-master.tar.gz;striplevel=1"
PVS_URI_SHA256 ??= "9f4c55dad2c121a4ca2ae39e2767eb4a214822ee34041a65692766ae438f96d8"

SRC_URI += "${PVS_URI};name=pv-developer-ca;subdir=pv-developer-ca_${PVS_VENDOR_NAME}"
SRC_URI[pv-developer-ca.sha256sum] = "${PVS_URI_SHA256}"

