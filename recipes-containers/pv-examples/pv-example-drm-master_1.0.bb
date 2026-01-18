SUMMARY = "Example DRM Master Container"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit core-image container-pvrexport

IMAGE_BASENAME = "pv-example-drm-master"

DEPENDS += "libdrm"
RDEPENDS:${PN} += "libdrm"
IMAGE_INSTALL += "libdrm"

SRC_URI += "file://pv-drm-master.c \
            file://${PN}.args.json"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} ${WORKDIR}/pv-drm-master.c -o pv-drm-master -ldrm -I${STAGING_INCDIR}/libdrm
}

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 pv-drm-master ${D}${bindir}/
}

FILES:${PN} += "${bindir}/pv-drm-master"

PVR_APP_ADD_EXTRA_ARGS += "--config=Entrypoint=/usr/bin/pv-drm-master"
