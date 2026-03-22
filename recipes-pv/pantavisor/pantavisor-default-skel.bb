
inherit pvrexport

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PVR_SRC_DIR = "${WORKDIR}/pantavisor-default-skel"

SRC_URI += " \
	file://pantavisor-default-skel/ \
"

# imx6ul/imx6ull/imx7 SoCs have DCP crypto engine
SRC_URI:append:mx6ul-generic-bsp  = " file://pv-imx-dcp/device-disks.json"
SRC_URI:append:mx6ull-generic-bsp = " file://pv-imx-dcp/device-disks.json"
SRC_URI:append:mx7-generic-bsp    = " file://pv-imx-dcp/device-disks.json"

# imx8m SoCs have CAAM crypto engine
SRC_URI:append:mx8m-generic-bsp = " file://pv-imx-caam/device-disks.json"

DEVICE_DISKS_FRAGMENT = ""
DEVICE_DISKS_FRAGMENT:mx6ul-generic-bsp  = "${WORKDIR}/pv-imx-dcp/device-disks.json"
DEVICE_DISKS_FRAGMENT:mx6ull-generic-bsp = "${WORKDIR}/pv-imx-dcp/device-disks.json"
DEVICE_DISKS_FRAGMENT:mx7-generic-bsp    = "${WORKDIR}/pv-imx-dcp/device-disks.json"
DEVICE_DISKS_FRAGMENT:mx8m-generic-bsp = "${WORKDIR}/pv-imx-caam/device-disks.json"

do_compile:append() {
    if [ -n "${DEVICE_DISKS_FRAGMENT}" ] && [ -f "${DEVICE_DISKS_FRAGMENT}" ]; then
        cd ${B}/pvrrepo
        ${PYTHON} ${THISDIR}/merge-device-json.py \
            device.json \
            "${DEVICE_DISKS_FRAGMENT}" \
            device.json.new
        mv device.json.new device.json
        pvr add device.json
        pvr commit
    fi
}
