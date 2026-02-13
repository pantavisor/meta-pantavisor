DESCRIPTION = "Pantavisor Flask Hello World Web Application"
HOMEPAGE = "https://pantavisor.io"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

SRC_URI = " \
    file://flask-app \
    file://templates/index.html \
    file://static/style.css \
"

inherit allarch

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/flask-app ${D}${bindir}/flask-helloworld
    
    install -d ${D}${datadir}/flask-helloworld/templates
    install -m 0644 ${WORKDIR}/templates/index.html ${D}${datadir}/flask-helloworld/templates/
    
    install -d ${D}${datadir}/flask-helloworld/static
    install -m 0644 ${WORKDIR}/static/style.css ${D}${datadir}/flask-helloworld/static/
}

RDEPENDS:${PN} += " \
    python3-core \
    python3-flask \
    python3-compression \
"

FILES:${PN} += " \
    ${datadir}/flask-helloworld \
"

BBCLASSEXTEND = "native nativesdk"

# Disable do_compile since we're just installing files
do_compile[noexec] = "1"