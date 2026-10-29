SUMMARY = "Intel 8265 Wi-Fi firmware, API 22, for the L4T 4.9 kernel"
DESCRIPTION = "The L4T 4.9 iwlwifi driver loads 8265 firmware API 22 to 26 \
only; current linux-firmware ships 34 and 36. 20230117 is the last release \
carrying iwlwifi-8265-22.ucode."
LICENSE = "Firmware-iwlwifi_firmware"
NO_GENERIC_LICENSE[Firmware-iwlwifi_firmware] = "LICENCE.iwlwifi_firmware"
LIC_FILES_CHKSUM = "file://LICENCE.iwlwifi_firmware;md5=2ce6786e0fc11ac6e36b54bb9b799f1b"

LF_URI = "https://gitlab.com/kernel-firmware/linux-firmware/-/raw/20230117"
SRC_URI = "\
    ${LF_URI}/iwlwifi-8265-22.ucode;name=fw;downloadfilename=linux-firmware-20230117-iwlwifi-8265-22.ucode \
    ${LF_URI}/LICENCE.iwlwifi_firmware;name=license;downloadfilename=linux-firmware-20230117-LICENCE.iwlwifi_firmware \
"
SRC_URI[fw.sha256sum] = "3bb830694ae4334559f601eaa1ca37096c655c7dbbdef7c68cfb47af8c9364a7"
SRC_URI[license.sha256sum] = "16d5040c7cf851fc693b7542e20870935b99802533ea1bfd231c377a2305e5c5"

S = "${WORKDIR}"

inherit allarch

do_unpack[postfuncs] += "rename_downloads"
rename_downloads() {
    cp -f ${WORKDIR}/linux-firmware-20230117-iwlwifi-8265-22.ucode ${WORKDIR}/iwlwifi-8265-22.ucode
    cp -f ${WORKDIR}/linux-firmware-20230117-LICENCE.iwlwifi_firmware ${WORKDIR}/LICENCE.iwlwifi_firmware
}

do_compile[noexec] = "1"

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    install -m 0644 ${WORKDIR}/iwlwifi-8265-22.ucode ${D}${nonarch_base_libdir}/firmware/
}

FILES:${PN} = "${nonarch_base_libdir}/firmware/iwlwifi-8265-22.ucode"
