
REMOVE_LIBTOOL_LA = "0"

DEPENDS:append = " pvr-native jq-native "

PVR_COMPRESSION ?= "-comp xz"

PANTAHUB_API ?= "api.pantahub.com"

S = "${WORKDIR}/pvrexport"

B = "${WORKDIR}/pvrbuild"

PVCONT_NAME = "${@'${BPN}'.replace('pv-', '')}"

do_compile(){
	cd ${B}
	pvr clone ${S} ${BPN}-${PV}
}

do_deploy(){
	cd ${B}/${BPN}-${PV}
	if [ -f ${WORKDIR}/${BPN}.mdev.json ]; then
		cp -f ${WORKDIR}/${BPN}.mdev.json ${PVCONT_NAME}/mdev.json
		pvr add ${PVCONT_NAME}/mdev.json
		pvr commit
	elif [ -f ${WORKDIR}/mdev.json ]; then
		cp -f ${WORKDIR}/mdev.json ${PVCONT_NAME}/
		pvr add ${PVCONT_NAME}/mdev.json
		pvr commit
        fi
	if [ -f ${WORKDIR}/${BPN}.args.json ]; then
		cat ${PVCONT_NAME}/src.json | jq --argfile args ${WORKDIR}/${BPN}.args.json \
		'. * { "args" : $args }' > ${PVCONT_NAME}/src.json.new
		mv ${PVCONT_NAME}/src.json.new ${PVCONT_NAME}/src.json
		pvr app install ${PVCONT_NAME}
	fi
	if [ -f ${WORKDIR}/${BPN}.config.json ]; then
		cat ${PVCONT_NAME}/src.json | jq --argfile config ${WORKDIR}/${BPN}.config.json \
		    '. * { "config" : $config }' > ${PVCONT_NAME}/src.json.new
		mv ${PVCONT_NAME}/src.json.new ${PVCONT_NAME}/src.json
		pvr app install ${PVCONT_NAME}
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

	pvr export ${DEPLOYDIR}/${BPN}-${PV}.pvrexport.tgz
	ln -fsr ${DEPLOYDIR}/${BPN}-${PV}.pvrexport.tgz ${DEPLOYDIR}/${BPN}.pvrexport.tgz
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

inherit deploy

