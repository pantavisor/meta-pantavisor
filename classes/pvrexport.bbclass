
REMOVE_LIBTOOL_LA = "0"

DEPENDS:append = " pvr-native jq-native "

PVR_COMPRESSION ?= "-comp xz"

PANTAHUB_API ?= "api.pantahub.com"

S = "${WORKDIR}/pvrexport"

B = "${WORKDIR}/pvrbuild"

do_compile[cleandirs] = "${B}"

do_compile(){
	cd ${B}
	pvr clone ${S} ${BPN}-${PV}
}

fakeroot do_deploy(){
	mkdir -p ${DEPLOY_DIR_IMAGE}/${DISTRO}/
	cd ${B}/${BPN}-${PV}
	if [ -f ${WORKDIR}/${BPN}.mdev.json ]; then
		cp -f ${WORKDIR}/${BPN}.mdev.json ${BPN}/mdev.json
		pvr add ${BPN}/mdev.json
		pvr commit
	elif [ -f ${WORKDIR}/mdev.json ]; then
		cp -f ${WORKDIR}/mdev.json ${BPN}/
		pvr add ${BPN}/mdev.json
		pvr commit
        fi
	if [ -f ${WORKDIR}/${BPN}.args.json ]; then
		cat ${BPN}/src.json | jq --argfile args ${WORKDIR}/${BPN}.args.json \
		'. * { "args" : $args }' > ${BPN}/src.json.new
		mv ${BPN}/src.json.new ${BPN}/src.json
		pvr app install ${BPN}
	fi
	if [ -f ${WORKDIR}/${BPN}.config.json ]; then
		cat ${BPN}/src.json | jq --argfile config ${WORKDIR}/${BPN}.config.json \
		    '. * { "config" : $config }' > ${BPN}/src.json.new
		mv ${BPN}/src.json.new ${BPN}/src.json
		pvr app install ${BPN}
	fi
	if [ -f "${WORKDIR}/pvs/key.default.pem" ]; then
		export PVR_SIG_KEY="${WORKDIR}/pvs/key.default.pem"
	fi
	if [ -f "${WORKDIR}/pvs/x5c.default.pem" ]; then
		export PVR_X5C_PATH="${WORKDIR}/pvs/x5c.default.pem"
	fi
	pvr commit
	pvr sig up
	pvr commit

	pvr export ${DEPLOY_DIR_IMAGE}/${DISTRO}/${BPN}-${PV}.pvrexport.tgz
	ln -fsr ${DEPLOY_DIR_IMAGE}/${DISTRO}/${BPN}-${PV}.pvrexport.tgz ${DEPLOY_DIR_IMAGE}/${DISTRO}/${BPN}.pvrexport.tgz
}

addtask deploy after do_compile

do_patch[noexec] = "1"
do_configure[noexec] = "1"
do_install[noexec] = "1"
do_package[noexec] = "1"
do_deploy_source_date_epoch[noexec] = "1"
do_populate_lic[noexect] = "1"
do_populate_sysroot[noexec] = "1"
do_package_qa[noexec] = "1"
do_packagedata[noexec] = "1"
do_package_write_ipk[noexec] = "1"
do_package_write_deb[noexec] = "1"
do_package_write_rpm[noexec] = "1"

