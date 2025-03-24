SRC_URI:remove = "file://boot.cmd.in"

SRC_URI:append = " file://boot.cmd.pvgeneric"

do_configure:prepend() {
    cp ${WORKDIR}/boot.cmd.pvgeneric ${WORKDIR}/boot.cmd.in
}

do_deploy() {
    mkimage -T script -C none -n "Distro boot script Pantavisor" -d boot.cmd boot.scr
    install -m 0644 boot.scr ${DEPLOYDIR}/boot.scr-${MACHINE}
}
