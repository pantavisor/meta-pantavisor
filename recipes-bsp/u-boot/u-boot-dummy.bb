

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PROVIDES = "virtual/bootloader"

# Stand-in bootloader: builds nothing, but must expose do_deploy so images and
# the pantavisor u-boot%.bbappend (which has a do_deploy:append) can depend on
# virtual/bootloader:do_deploy like they would for a real u-boot.
inherit deploy

do_deploy() {
    :
}
addtask deploy after do_compile before do_build

