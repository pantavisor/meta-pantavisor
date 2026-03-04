#
# pv-tezi-uboot class - Configures u-boot environment for Pantavisor TEZI
#
# This class is designed to be included in machine configurations for Toradex boards
# that support pv_teziimg. It provides the necessary configuration but doesn't
# directly modify u-boot - instead it sets variables that the image recipes use.
#
# Usage: Add to IMAGE_CLASSES for Toradex machines:
#   IMAGE_CLASSES:append = " pv-tezi-uboot"
#

PV_TEZI_UBOOT_NAND_MACHINES ?= "colibri-imx6ull"
PV_TEZI_UBOOT_EMMC_MACHINES ?= "verdin-imx8mm"

python () {
    machine = d.getVar('MACHINE')
    nand_machines = (d.getVar('PV_TEZI_UBOOT_NAND_MACHINES') or "").split()
    emmc_machines = (d.getVar('PV_TEZI_UBOOT_EMMC_MACHINES') or "").split()

    is_toradex = machine in nand_machines or machine in emmc_machines
    
    if is_toradex:
        # Add dependency on tezi metadata
        d.appendVar('WKS_FILE_DEPENDS', ' pantavisor-tezi-metadata')
        
        # Set flash type based on machine
        if machine in nand_machines:
            d.setVar('PV_TEZI_FLASH_TYPE', 'rawnand')
        else:
            d.setVar('PV_TEZI_FLASH_TYPE', 'emmc')
}
