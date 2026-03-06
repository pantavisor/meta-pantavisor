SUMMARY = "Pantavisor TEZI metadata files"
DESCRIPTION = "Provides Pantavisor-specific branding for TEZI images"
LICENSE = "CLOSED"

DEPLOYDIR ?= "${WORKDIR}/deploy"

SRC_URI = " \
    file://pantacor.png \
    file://marketing.tar \
"

do_deploy() {
    mkdir -p ${DEPLOYDIR}
    if [ -f "${WORKDIR}/pantacor.png" ]; then
        install -m 644 ${WORKDIR}/pantacor.png ${DEPLOYDIR}/
    fi
    if [ -f "${WORKDIR}/marketing.tar" ]; then
        install -m 644 ${WORKDIR}/marketing.tar ${DEPLOYDIR}/
    fi
}

addtask deploy after do_compile before do_build

INSANE_SKIP:${PN} = "license-checksum"
