
PVS_VENDOR_NAME ??= "generic"
PVS_URI ??= "git://gitlab.com/pantacor/pv-developer-ca;protocol=https;branch=master;rev=2340d747c4acd0a1a702b3d7d5acc014b51daaa7"
SRC_URI += "${PVS_URI};subdir=pv-developer-ca_${PVS_VENDOR_NAME}"

