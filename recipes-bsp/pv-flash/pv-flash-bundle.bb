SUMMARY = "Factory flash archive for Pantavisor images"
DESCRIPTION = "Assembles a tar.gz containing the Pantavisor image, \
recovery U-Boot, UUU binary, and flashing scripts."
LICENSE = "CLOSED"

inherit deploy

FILESEXTRAPATHS:prepend := "${THISDIR}/files/${MACHINE}:${THISDIR}/files:"

# Image recipe whose rootfs goes into the bundle.
PV_FLASH_IMAGE ?= "pantavisor-starter"

# Recovery multiconfig name — must match a BBMULTICONFIG entry in local.conf.
PV_FLASH_RECOVERY_MC ?= ""

# Recipe name to build in the recovery multiconfig (e.g. u-boot-toradex).
PV_FLASH_RECOVERY_RECIPE ?= ""

# Filename of the recovery U-Boot image in the recovery multiconfig deploy dir.
PV_FLASH_RECOVERY_IMAGE ?= ""

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

PV_FLASH_FLASH_SCRIPT_IN ?= ""
PV_FLASH_FLASH_SCRIPT_IN:verdin-imx8mm = "file://flash.sh.in"
PV_FLASH_FLASH_SCRIPT_IN:colibri-imx6ull = "file://flash.sh.in"

SRC_URI = "${PV_FLASH_UUU_SCRIPT_IN} ${PV_FLASH_FLASH_SCRIPT_IN}"

RECOVERY_DEPLOY_DIR_IMAGE = "${TOPDIR}/tmp-${DISTRO_CODENAME}-${PV_FLASH_RECOVERY_MC}/deploy/images/${MACHINE}"

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_deploy[depends] += "${PV_FLASH_IMAGE}:do_image_complete \
                       uuu-native:do_populate_sysroot \
                       patchelf-native:do_populate_sysroot"

do_deploy[mcdepends] += "${@('mc::' + d.getVar('PV_FLASH_RECOVERY_MC') + ':' + d.getVar('PV_FLASH_RECOVERY_RECIPE') + ':do_deploy') \
    if (d.getVar('PV_FLASH_RECOVERY_MC') and d.getVar('PV_FLASH_RECOVERY_RECIPE') and \
        d.getVar('PV_FLASH_RECOVERY_MC') in (d.getVar('BBMULTICONFIG') or '').split()) \
    else ''}"

do_deploy() {
    local bundle_name="${PN}-${MACHINE}"
    local bundle_dir="${WORKDIR}/${bundle_name}"
    local wic="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic"
    local wic_gz="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic.gz"
    local wic_bmap="${PV_FLASH_IMAGE}-${MACHINE}.rootfs.wic.bmap"

    rm -rf "${bundle_dir}"
    mkdir -p "${bundle_dir}"

    if [ -n "${PV_FLASH_UBIFS}" ]; then
        install -m 644 "${DEPLOY_DIR_IMAGE}/${PV_FLASH_UBIFS}" "${bundle_dir}/${PV_FLASH_UBIFS}"
    else
        install -m 644 "${DEPLOY_DIR_IMAGE}/${wic_gz}" "${bundle_dir}/${wic_gz}"
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

    install -m 755 "${STAGING_BINDIR_NATIVE}/uuu" "${bundle_dir}/uuu"
    patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 \
             --set-rpath "" \
             "${bundle_dir}/uuu"

    if [ -f "${WORKDIR}/uuu.auto.in" ]; then
        sed -e "s|@WIC@|${wic}|g" \
            -e "s|@WIC_GZ@|${wic_gz}|g" \
            -e "s|@UBIFS@|${PV_FLASH_UBIFS}|g" \
            -e "s|@UBOOT_NAND@|${PV_FLASH_NAND_UBOOT}|g" \
            -e "s|@RECOVERY_IMAGE@|${PV_FLASH_RECOVERY_IMAGE}|g" \
            "${WORKDIR}/uuu.auto.in" > "${bundle_dir}/uuu.auto"
    fi

    if [ -f "${WORKDIR}/flash.sh.in" ]; then
        sed -e "s|@WIC@|${wic}|g" \
            -e "s|@WIC_GZ@|${wic_gz}|g" \
            -e "s|@UBIFS@|${PV_FLASH_UBIFS}|g" \
            -e "s|@UBOOT_NAND@|${PV_FLASH_NAND_UBOOT}|g" \
            -e "s|@RECOVERY_IMAGE@|${PV_FLASH_RECOVERY_IMAGE}|g" \
            "${WORKDIR}/flash.sh.in" > "${bundle_dir}/flash.sh"
        chmod 755 "${bundle_dir}/flash.sh"
    fi

    tar -czf "${DEPLOYDIR}/${bundle_name}.tar.gz" \
        -C "${WORKDIR}" "${bundle_name}"

    ln -sfn "${bundle_name}.tar.gz" \
        "${DEPLOYDIR}/${PN}-${MACHINE}-latest.tar.gz"
}

addtask deploy after do_compile before do_build
