DESCRIPTION = "pvcontrol tools from pvr-sdk"
LICENSE = "CLOSED"
PR = "r1"

SRC_URI = "file://pvcontrol \
           file://pvtx \
           file://JSON.sh \
           "

RDEPENDS:${PN} = "curl"

PACKAGES =+ "${PN}-pvtx"
FILES:${PN}-pvtx += "${bindir}/pvtx"

S = "${WORKDIR}"

inherit allarch

do_install() {
	mkdir -p ${D}${bindir}
        install -m 0755 ${S}/pvcontrol ${D}${bindir}
        install -m 0755 ${S}/pvtx ${D}${bindir}
        install -m 0755 ${S}/JSON.sh ${D}${bindir}
}

