
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

# Override individual pantahub.config keys without editing the shipped file.
# Set as varflags from a distro/machine/image config or local.conf, e.g.:
#   PANTAHUB_CONFIG[creds.host]     = "api.stage.pantahub.com"
#   PANTAHUB_CONFIG[control.remote] = "0"
#   PANTAHUB_CONFIG[log.push]       = "false"
# A flag whose key already exists in pantahub.config rewrites that line; a new
# key is appended. Values must not contain whitespace.
PANTAHUB_CONFIG ?= ""

python () {
    # getVarFlags' 'expand' arg is an iterable of flag names to expand in this
    # bitbake (not a bool), so expand=True raises "argument of type 'bool' is
    # not iterable" once any PANTAHUB_CONFIG[flag] is set. Fetch the flags plain
    # and expand each value ourselves.
    overrides = []
    for key, val in sorted((d.getVarFlags('PANTAHUB_CONFIG') or {}).items()):
        overrides.append("%s=%s" % (key, d.expand(val)))
    d.setVar('PANTAHUB_CONFIG_OVERRIDES', ' '.join(overrides))
}

fakeroot do_install() {
    install -d -m 0755 ${D}/boot
    install -d -m 0755 ${D}/config
    install -d -m 0755 ${D}/logs
    install -d -m 0755 ${D}/objects
    install -d -m 0755 ${D}/trails
    install -d -m 0755 ${D}/trails/0

    install -m 0755 ${WORKDIR}/uboot.txt ${D}/boot/uboot.txt
    install -m 0755 ${WORKDIR}/pantahub.config ${D}/config/
    cfg="${D}/config/pantahub.config"
    for kv in ${PANTAHUB_CONFIG_OVERRIDES}; do
        key="${kv%%=*}"
        val="${kv#*=}"
        rkey="$(printf '%s' "$key" | sed 's/[.[\\*^$/]/\\&/g')"
        rval="$(printf '%s' "$val" | sed 's/[\\&|]/\\&/g')"
        if grep -q "^${rkey}=" "$cfg"; then
            sed -i "s|^${rkey}=.*|${key}=${rval}|" "$cfg"
        else
            echo "${key}=${val}" >> "$cfg"
        fi
    done

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
