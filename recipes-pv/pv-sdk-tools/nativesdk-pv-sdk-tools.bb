SUMMARY = "Pack a container root filesystem into a Pantavisor pvrexport"
DESCRIPTION = "SDK-side counterpart of container-pvrexport.bbclass: \
pv-mkpvrexport turns a rootfs directory into a signed <name>.pvrexport.tgz \
outside of BitBake."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit pvr-ca nativesdk

SRC_URI += "file://pv-mkpvrexport"

S = "${WORKDIR}"

# cmake is not used by pv-mkpvrexport: it is here so the SDK can build
# pantavisor.
RDEPENDS:${PN} = " \
	nativesdk-cmake \
	nativesdk-jq \
	nativesdk-pvr \
	nativesdk-squashfs-tools \
"

do_install() {
	install -Dm 0755 ${WORKDIR}/pv-mkpvrexport ${D}${bindir}/pv-mkpvrexport
	# Same developer keys container-pvrexport signs with, so an SDK-built
	# container verifies on a device that accepts CI-built ones.
	install -Dm 0644 ${WORKDIR}/pv-developer-ca_${PVS_VENDOR_NAME}/pvs/pvs.defaultkeys.tar.gz \
		${D}${datadir}/pv-sdk/pvs.defaultkeys.tar.gz
}

FILES:${PN} += "${datadir}/pv-sdk"
