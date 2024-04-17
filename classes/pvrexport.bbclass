
inherit deploy pvr-ca dockerarch

REMOVE_LIBTOOL_LA = "0"

DEPENDS += "pvr-native jq-native"

PVR_COMPRESSION ?= "-comp xz"

PANTAHUB_API ?= "api.pantahub.com"

PVCONT_NAME = "${@'${BPN}'.replace('pv-', '')}"

PVR_CONFIG_DIR ?= "${WORKDIR}/pvrconfig"
PVR_SRC_DIR = "${WORKDIR}/pvrsrc"
PVR_TMPDIR = "${WORKDIR}/tmp"
PVR_HOME_DIR = "${WORKDIR}/home"

PVR_SRC_URI ?= ""
PVR_DOCKER_REF ?= ""
PVR_APP_ADD_EXTRA_ARGS ?= ""

do_fetch_pvr[dirs] += "${PVR_CONFIG_DIR}"
do_fetch_pvr[cleandirs] += "${PVR_SRC_DIR} ${PVR_TMPDIR}"
do_fetch_pvr[depends] += "pvr-native:do_populate_sysroot squashfs-tools-native:do_populate_sysroot"
do_fetch_pvr[network] = "1"

PSEUDO_IGNORE_PATHS .= ",${PVR_SRC_DIR},${PVR_CONFIG_DIR},${PVR_HOME_DIR}"

fakeroot do_fetch_pvr() {
	export PVR_DISABLE_SELF_UPGRADE=true
	export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
	export TMPDIR="${PVR_TMPDIR}"
	export HOME="${PVR_HOME_DIR}"
	echo "do_fetch_pvr: ${PVR_SRC_DIR}"
	cd ${PVR_SRC_DIR}
	if [ -n "${PVR_SRC_URI}" ]; then
		echo "creating pvr repo empty at $PWD"
		pvr init
		echo "getting remote pvr repo ${PVR_SRC_URI}"
		pvr get ${PVR_SRC_URI}
	elif [ -n "${PVR_DOCKER_REF}" ]; then
		echo "pvr app add from docker ${PVR_DOCKER_REF}"
		pvr init
		echo "pvr app add from docker ${PVR_DOCKER_REF}"
		pvr init
		pvr app add --platform="${DOCKER_PLATFORM}" --from="${PVR_DOCKER_REF}" ${PVR_APP_ADD_EXTRA_ARGS} "${PVCONT_NAME}"
		pvr add .
		pvr commit
	fi
}

addtask do_fetch_pvr after do_fetch before do_unpack

do_unpack[postfuncs] += "do_unpack_pvr"
do_unpack_pvr() {
	export PVR_DISABLE_SELF_UPGRADE=true
	export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"
	if [ -d ${WORKDIR}/pv-developer-ca_generic ]; then
		tar -C ${PVR_CONFIG_DIR}/ -xf ${WORKDIR}/pv-developer-ca_generic/pvs/pvs.defaultkeys.tar.gz
	fi
	echo "do_unpack_pvr: $PWD ${B}/pvrrepo"
	mkdir -p ${B}/pvrrepo
	cd ${B}/pvrrepo
	if [ -d "${PVR_SRC_DIR}/.pvr" ]; then
		echo "getting from clonedir ${PVR_SRC_DIR}"
		pvr init
		pvr get ${PVR_SRC_DIR}/.pvr
	fi
	pvr checkout
	if [ -f "_sigs/${PVCONT_NAME}.json" ]; then
		pvr sig up _sigs/${PVCONT_NAME}.json
	else
		pvr sig add -n --part ${PVCONT_NAME}
	fi
	pvr commit
}

do_compile[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_compile(){
	export PVR_DISABLE_SELF_UPGRADE=true
	export PVR_CONFIG_DIR="${PVR_CONFIG_DIR}"

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
		cat ${PVCONT_NAME}/src.json | jq --slurpfile args ${WORKDIR}/${BPN}.args.json \
		'. * { "args" : $args[0] }' > ${PVCONT_NAME}/src.json.new
		mv ${PVCONT_NAME}/src.json.new ${PVCONT_NAME}/src.json
		pvr app install ${PVCONT_NAME}
	fi
	if [ -f ${WORKDIR}/${BPN}.config.json ]; then
		cat ${PVCONT_NAME}/src.json | jq --slurpfile config ${WORKDIR}/${BPN}.config.json \
		    '. * { "config" : $config[0] }' > ${PVCONT_NAME}/src.json.new
		mv ${PVCONT_NAME}/src.json.new ${PVCONT_NAME}/src.json
		pvr app install ${PVCONT_NAME}
	fi
	if [ -f "${WORKDIR}/pvs/key.default.pem" ]; then
		export PVR_SIG_KEY="${WORKDIR}/pvs/key.default.pem"
	fi
	if [ -f "${WORKDIR}/pvs/x5c.default.pem" ]; then
		export PVR_X5C_PATH="${WORKDIR}/pvs/x5c.default.pem"
	fi
	pvr add
	pvr commit
	pvr sig up
	pvr commit
}

do_deploy[dirs] += "${PVR_CONFIG_DIR} ${B}/pvrrepo"

do_deploy(){
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


