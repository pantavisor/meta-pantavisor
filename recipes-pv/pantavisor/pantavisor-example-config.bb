DESCRIPTION = "Pantavisor example config provider — template + policy overlay"
SECTION = "base"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Renders /etc/pantavisor.config from a shipped .in template using the
# upstream PV_* ABI, then overlays a couple of policy tweaks. Other /etc
# bits (resolv.conf, /etc/pantavisor/{pvs,policies,ssh}) are installed
# alongside via do_install:append; they are independent of the config
# provider contract.

inherit pantavisor-config-provider pvr-ca

SRC_URI += "file://pantavisor.config.in"
SRC_URI += "file://etcdir/"

# Mode C overlay: drop the debug shell and quieten logging to INFO.
PV_CONFIG_SET = "PV_LOG_LEVEL=3 PV_DEBUG_SHELL=0"

FILES:${PN} += "${sysconfdir}/pantavisor/"
FILES:${PN} += "${sysconfdir}/resolv.conf"

do_install:append() {
	# Drop in the auxiliary /etc payload (CA trust store, ssh keys readme,
	# secureboot policy). pantavisor.config itself was already installed
	# by the bbclass — skip it here, the template above is authoritative.
	rm -f ${WORKDIR}/etcdir/pantavisor.config || true
	cp -rf ${WORKDIR}/etcdir/. ${D}${sysconfdir}/
}
