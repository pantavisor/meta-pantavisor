
PVS_VENDOR_NAME ??= "generic"
PVS_URI ??= "git://gitlab.com/pantacor/pv-developer-ca;protocol=https;branch=master;rev=2340d747c4acd0a1a702b3d7d5acc014b51daaa7"
PVS_URI_SHA256 ??= "c5fbca13f400337749766b7daf5233f333b2358afa1fa5eaa4580b91e737daad"

SRC_URI += "${PVS_URI};name=pv-developer-ca;subdir=pv-developer-ca_${PVS_VENDOR_NAME}"
SRC_URI[pv-developer-ca.sha256sum] = "${PVS_URI_SHA256}"

