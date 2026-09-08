SUMMARY = "Factory flash archive for Pantavisor images"
DESCRIPTION = "Assembles a tar.gz containing the Pantavisor image, a boot/recovery \
loader, the host flashing tool (NXP UUU or Rockchip rkdeveloptool), and flashing scripts."
LICENSE = "CLOSED"

inherit deploy

FILESEXTRAPATHS:prepend := "${THISDIR}/files/${MACHINE}:${THISDIR}/files:"

# Image recipe whose rootfs goes into the bundle.
PV_FLASH_IMAGE ?= "pantavisor-starter"

# Host flashing tool bundled and driven by flash.sh:
#   "uuu"          - NXP i.MX, SDP/fastboot download mode
#   "rkdeveloptool" - Rockchip, USB Maskrom/Loader mode
PV_FLASH_TOOL ?= "uuu"
PV_FLASH_TOOL:orangepi-5b = "rkdeveloptool"

# rkdeveloptool only: glob for the Rockchip USB loader (DDR init + miniloader/
# usbplug) in the main build's DEPLOY_DIR_IMAGE. Installed into the bundle as the
# fixed name "loader.bin" and passed to "rkdeveloptool db".
PV_FLASH_RK_LOADER ?= ""
PV_FLASH_RK_LOADER:orangepi-5b = "loader.bin"

# Recovery multiconfig name — must match a BBMULTICONFIG entry in local.conf.
PV_FLASH_RECOVERY_MC ?= ""

# Recipe name to build in the recovery multiconfig (e.g. u-boot-toradex).
PV_FLASH_RECOVERY_RECIPE ?= ""

# Filename of the recovery U-Boot image in the recovery multiconfig deploy dir.
PV_FLASH_RECOVERY_IMAGE ?= ""

# Glob for a boot binary sourced directly from the main build's
# DEPLOY_DIR_IMAGE instead of a separate recovery multiconfig — for machines
# whose production bootloader already enters SDP/fastboot download mode on
# its own (e.g. NXP-standard i.MX8M ROM boot-source detection), unlike
# Toradex's distro_bootcmd override which requires a stripped recovery build.
# Installed into the bundle as the fixed name "imx-boot.bin".
PV_FLASH_BOOT_IMAGE ?= ""
PV_FLASH_BOOT_IMAGE:imx8mm-var-dart = "imx-boot-imx8mm-var-dart*.bin-*"
PV_FLASH_BOOT_IMAGE:imx8mn-var-som = "imx-boot-imx8mn-var-som*.bin-*"
PV_FLASH_BOOT_IMAGE:imx8qxp-b0-mek = "imx-boot-imx8qxp-b0-mek*.bin-*"

# For NAND machines: production NAND U-Boot binary filename in the recovery
# multiconfig deploy dir (the same tezi-recovery build also produces the rawnand
# config; set to "" on eMMC machines).
PV_FLASH_NAND_UBOOT ?= ""
PV_FLASH_NAND_UBOOT:colibri-imx6ull = "u-boot.imx-rawnand"

# For NAND machines: UBIFS image filename in the main build deploy dir.
# Leave empty on eMMC machines (uses .wic.gz instead).
PV_FLASH_UBIFS ?= ""
PV_FLASH_UBIFS:colibri-imx6ull = "${PV_FLASH_IMAGE}-${MACHINE}.rootfs.ubifs"

# SRC_URI entries for machine-specific script templates.
PV_FLASH_UUU_SCRIPT_IN ?= ""
PV_FLASH_UUU_SCRIPT_IN:verdin-imx8mm = "file://uuu.auto.in"
PV_FLASH_UUU_SCRIPT_IN:colibri-imx6ull = "file://uuu.auto.in"
PV_FLASH_UUU_SCRIPT_IN:imx8mm-var-dart = "file://uuu.auto.in"
PV_FLASH_UUU_SCRIPT_IN:imx8mn-var-som = "file://uuu.auto.in"
PV_FLASH_UUU_SCRIPT_IN:imx8qxp-b0-mek = "file://uuu.auto.in"

PV_FLASH_FLASH_SCRIPT_IN ?= ""
PV_FLASH_FLASH_SCRIPT_IN:verdin-imx8mm = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:colibri-imx6ull = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:imx8mm-var-dart = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:imx8mn-var-som = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:imx8qxp-b0-mek = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:orangepi-5b = "file://flash.sh.in"

# Optional README.md.in shipped inside the bundle (host prerequisites, etc.),
# sed-expanded with the same @WIC*@ placeholders as the flash scripts.
PV_FLASH_README_IN ?= ""
PV_FLASH_README_IN:orangepi-5b = "file://README.md.in"

SRC_URI = "${PV_FLASH_UUU_SCRIPT_IN} ${PV_FLASH_FLASH_SCRIPT_IN} ${PV_FLASH_README_IN}"

RECOVERY_DEPLOY_DIR_IMAGE = "${TOPDIR}/tmp-${DISTRO_CODENAME}-${PV_FLASH_RECOVERY_MC}/deploy/images/${MACHINE}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_deploy[depends] += "${PV_FLASH_IMAGE}:do_image_complete \
                       patchelf-native:do_populate_sysroot"

# Pull only the flashing tool the machine actually uses. rkdeveloptool needs the
# Rockchip loader, deployed by virtual/bootloader in the same build.
do_deploy[depends] += "${@'uuu-native:do_populate_sysroot' if d.getVar('PV_FLASH_TOOL') == 'uuu' \
    else 'rkdeveloptool-native:do_populate_sysroot virtual/bootloader:do_deploy'}"

do_deploy[mcdepends] += "${@('mc::' + d.getVar('PV_FLASH_RECOVERY_MC') + ':' + d.getVar('PV_FLASH_RECOVERY_RECIPE') + ':do_deploy') \
    if (d.getVar('PV_FLASH_RECOVERY_MC') and d.getVar('PV_FLASH_RECOVERY_RECIPE') and \
        d.getVar('PV_FLASH_RECOVERY_MC') in (d.getVar('BBMULTICONFIG') or '').split()) \
    else ''}"

do_deploy() {
    local bundle_name="${PN}-${MACHINE}"
    local bundle_dir="${WORKDIR}/${bundle_name}"
    local wic="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic"
    local wic_gz="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic.gz"
    local wic_zst="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic.zst"
    local wic_bmap="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic.bmap"

    rm -rf "${bundle_dir}"
    mkdir -p "${bundle_dir}"

    if [ -n "${PV_FLASH_UBIFS}" ]; then
        install -m 644 "${DEPLOY_DIR_IMAGE}/${PV_FLASH_UBIFS}" "${bundle_dir}/${PV_FLASH_UBIFS}"
    else
        if [ -f "${DEPLOY_DIR_IMAGE}/${wic_zst}" ]; then
            install -m 644 "${DEPLOY_DIR_IMAGE}/${wic_zst}" "${bundle_dir}/${wic_zst}"
        fi

        if [ -f "${DEPLOY_DIR_IMAGE}/${wic_gz}" ]; then
            install -m 644 "${DEPLOY_DIR_IMAGE}/${wic_gz}" "${bundle_dir}/${wic_gz}"
        fi

        # Some Rockchip image configs emit an uncompressed .wic only.
        if [ ! -f "${DEPLOY_DIR_IMAGE}/${wic_zst}" ] && \
           [ ! -f "${DEPLOY_DIR_IMAGE}/${wic_gz}" ] && \
           [ -f "${DEPLOY_DIR_IMAGE}/${wic}" ]; then
            install -m 644 "${DEPLOY_DIR_IMAGE}/${wic}" "${bundle_dir}/${wic}"
        fi

        if [ -f "${DEPLOY_DIR_IMAGE}/${wic_bmap}" ]; then
            install -m 644 "${DEPLOY_DIR_IMAGE}/${wic_bmap}" "${bundle_dir}/${wic_bmap}"
        fi
    fi

    if [ -n "${PV_FLASH_RECOVERY_IMAGE}" ]; then
        install -m 644 \
            "${RECOVERY_DEPLOY_DIR_IMAGE}/${PV_FLASH_RECOVERY_IMAGE}" \
            "${bundle_dir}/${PV_FLASH_RECOVERY_IMAGE}"
    fi

    if [ -n "${PV_FLASH_NAND_UBOOT}" ]; then
        install -m 644 \
            "${RECOVERY_DEPLOY_DIR_IMAGE}/${PV_FLASH_NAND_UBOOT}" \
            "${bundle_dir}/${PV_FLASH_NAND_UBOOT}"
    fi

    if [ -n "${PV_FLASH_BOOT_IMAGE}" ]; then
        install -m 644 \
            $(ls ${DEPLOY_DIR_IMAGE}/${PV_FLASH_BOOT_IMAGE} | head -n1) \
            "${bundle_dir}/imx-boot.bin"
    fi

    # patchelf re-points the tool's ELF interpreter/rpath so it runs on an
    # arbitrary x86-64 Linux host regardless of the build sysroot.
    if [ "${PV_FLASH_TOOL}" = "rkdeveloptool" ]; then
        install -m 755 "${STAGING_BINDIR_NATIVE}/rkdeveloptool" "${bundle_dir}/rkdeveloptool"
        patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
                 --set-rpath "" \
                 "${bundle_dir}/rkdeveloptool"
        install -m 644 \
            $(ls ${DEPLOY_DIR_IMAGE}/${PV_FLASH_RK_LOADER} | head -n1) \
            "${bundle_dir}/loader.bin"
    else
        install -m 755 "${STAGING_BINDIR_NATIVE}/uuu" "${bundle_dir}/uuu"
        patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
                 --set-rpath "" \
                 "${bundle_dir}/uuu"
    fi

    if [ -f "${WORKDIR}/uuu.auto.in" ]; then
        sed -e "s|@WIC@|${wic}|g" \
            -e "s|@WIC_GZ@|${wic_gz}|g" \
            -e "s|@WIC_ZST@|${wic_zst}|g" \
            -e "s|@UBIFS@|${PV_FLASH_UBIFS}|g" \
            -e "s|@UBOOT_NAND@|${PV_FLASH_NAND_UBOOT}|g" \
            -e "s|@RECOVERY_IMAGE@|${PV_FLASH_RECOVERY_IMAGE}|g" \
            "${WORKDIR}/uuu.auto.in" > "${bundle_dir}/uuu.auto"
    fi

    if [ -f "${WORKDIR}/flash.sh.in" ]; then
        sed -e "s|@WIC@|${wic}|g" \
            -e "s|@WIC_GZ@|${wic_gz}|g" \
            -e "s|@WIC_ZST@|${wic_zst}|g" \
            -e "s|@UBIFS@|${PV_FLASH_UBIFS}|g" \
            -e "s|@UBOOT_NAND@|${PV_FLASH_NAND_UBOOT}|g" \
            -e "s|@RECOVERY_IMAGE@|${PV_FLASH_RECOVERY_IMAGE}|g" \
            "${WORKDIR}/flash.sh.in" > "${bundle_dir}/flash.sh"
        chmod 755 "${bundle_dir}/flash.sh"
    fi

    if [ -f "${WORKDIR}/README.md.in" ]; then
        sed -e "s|@WIC@|${wic}|g" \
            -e "s|@WIC_GZ@|${wic_gz}|g" \
            -e "s|@WIC_ZST@|${wic_zst}|g" \
            -e "s|@UBIFS@|${PV_FLASH_UBIFS}|g" \
            -e "s|@UBOOT_NAND@|${PV_FLASH_NAND_UBOOT}|g" \
            -e "s|@RECOVERY_IMAGE@|${PV_FLASH_RECOVERY_IMAGE}|g" \
            "${WORKDIR}/README.md.in" > "${bundle_dir}/README.md"
    fi

    tar -czf "${DEPLOYDIR}/${bundle_name}.tar.gz" \
        -C "${WORKDIR}" "${bundle_name}"

    ln -sfn "${bundle_name}.tar.gz" \
        "${DEPLOYDIR}/${PN}-${MACHINE}-latest.tar.gz"
}

addtask deploy after do_compile before do_build
