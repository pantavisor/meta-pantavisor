
inherit allarch deploy image-artifact-names

DESCRIPTION = "Pantavisor pvroot skeleton package"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS += "pvr-native"

FILES:${PN} += " \
	${root_prefix}/boot/* \
	${root_prefix}/config/* \
	${root_prefix}/logs/** \
	${root_prefix}/objects/** \
	${root_prefix}/trails/** \
"

SRC_URI += " \
	file://pantahub.config \
	file://pvrconfig \
	file://uboot.txt \
"
PSEUDO_IGNORE_PATHS .= ",/tmp,${DEPLOYDIR}"

fakeroot do_install() {
    install -d -m 0755 ${D}/boot
    install -d -m 0755 ${D}/config
    install -d -m 0755 ${D}/logs
    install -d -m 0755 ${D}/objects
    install -d -m 0755 ${D}/trails
    install -d -m 0755 ${D}/trails/0

    install -m 0755 ${WORKDIR}/uboot.txt ${D}/boot/uboot.txt
    install -m 0755 ${WORKDIR}/pantahub.config ${D}/config/
    cd ${D}/trails/0/
    echo "pvr init ..."
    export PVR_DISABLE_SELF_UPGRADE=true
    pvr init --objects=../../objects
    echo "pvr add ..."
    pvr add
    echo "pvr commit ..."
    pvr commit
    chown -R 0:0 ${D}/trails/

    echo tar -C "${D}" -cvzf ${B}/${IMAGE_NAME}.tar.gz .
    tar -C "${D}" -cvzf ${B}/${IMAGE_NAME}.tar.gz .
}


do_deploy() {
    cp -f ${B}/${IMAGE_NAME}.tar.gz ${DEPLOYDIR}/${IMAGE_NAME}.tar.gz
    ln -sf ${IMAGE_NAME}.tar.gz ${DEPLOYDIR}/${IMAGE_LINK_NAME}.tar.gz
}

addtask deploy after do_install
