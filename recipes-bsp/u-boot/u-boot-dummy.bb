LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PROVIDES = "virtual/bootloader u-boot"
RPROVIDES:${PN} = "u-boot"

ALLOW_EMPTY:${PN} = "1"

inherit deploy

do_deploy() {
    :
}

addtask deploy before do_build
