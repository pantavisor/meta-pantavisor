SUMMARY = "RPi EEPROM firmware binaries for auto-update"
DESCRIPTION = "Deploys recovery.bin and pieeprom binaries for Pi 4 (2711) \
and Pi 5 (2712) EEPROM auto-update on first boot."
LICENSE = "BSD-3-Clause & Broadcom-RPi"
LIC_FILES_CHKSUM = "file://LICENSE;md5=a6c5149578a16272119f3f9c13d6549b"

# Same source as meta-raspberrypi's rpi-eeprom recipe
SRC_URI = "git://github.com/raspberrypi/rpi-eeprom.git;protocol=https;branch=master"
SRCREV = "1bd0a1052b2e74d7af04de18d30b5edb12d8a423"
PV = "v2025.03.10"

S = "${WORKDIR}/git"

inherit deploy

# Nothing to compile
do_compile[noexec] = "1"
do_configure[noexec] = "1"

do_deploy() {
    install -d ${DEPLOYDIR}/rpi-eeprom-fw

    # Pi 4 (BCM2711)
    install -m 0644 ${S}/firmware-2711/latest/recovery.bin \
        ${DEPLOYDIR}/rpi-eeprom-fw/recovery-2711.bin
    latest_2711=$(ls -1 ${S}/firmware-2711/latest/pieeprom-*.bin | sort | tail -1)
    install -m 0644 "$latest_2711" ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2711.bin
    sha256sum ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2711.bin | awk '{print $1}' \
        > ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2711.sig

    # Pi 5 (BCM2712)
    install -m 0644 ${S}/firmware-2712/latest/recovery.bin \
        ${DEPLOYDIR}/rpi-eeprom-fw/recovery-2712.bin
    latest_2712=$(ls -1 ${S}/firmware-2712/latest/pieeprom-*.bin | sort | tail -1)
    install -m 0644 "$latest_2712" ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2712.bin
    sha256sum ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2712.bin | awk '{print $1}' \
        > ${DEPLOYDIR}/rpi-eeprom-fw/pieeprom-2712.sig
}

addtask deploy after do_install
