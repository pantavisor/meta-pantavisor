FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://pantacor.png \
    file://marketing.tar;unpack=false \
"
do_install:append() {
    install -m 644 ${WORKDIR}/pantacor.png ${DEPLOYDIR}
}
