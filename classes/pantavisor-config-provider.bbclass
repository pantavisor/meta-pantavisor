# pantavisor-config-provider.bbclass
#
# Single class for shipping a /etc/pantavisor.config that replaces the
# upstream "pantavisor-config" subpackage. One linear render pipeline:
#
#   1. base = upstream-rendered /etc/pantavisor.config (from sysroot)
#   2. if the recipe ships pantavisor.config      -> replace base with it
#      XOR
#      if the recipe ships pantavisor.config.in   -> render and replace base
#   3. apply PV_CONFIG_SET   (replace-if-present, append-if-absent)
#
# Each step is optional. A recipe that sets neither file nor overlay just
# repackages the upstream default (useful as a packaging seam). Strictly
# only one of pantavisor.config / pantavisor.config.in may be shipped.
#
# Templates use the public PV_* ABI documented in pantavisor's CMake. The
# variable list is staged at ${STAGING_DATADIR}/pantavisor/pantavisor-vars.env
# by the pantavisor recipe; consumers do not need to know which PV_* vars
# exist, only which ones their template references.
#
# Usage (overlay-only — common case):
#   inherit pantavisor-config-provider
#   PV_CONFIG_SET = "PV_STORAGE_FIRMWARE_VOL=1"
#
# Usage (verbatim):
#   inherit pantavisor-config-provider
#   SRC_URI += "file://pantavisor.config"
#
# Usage (templated):
#   inherit pantavisor-config-provider
#   SRC_URI += "file://pantavisor.config.in"

DEPENDS += "pantavisor"

PROVIDES += "pantavisor-config"
RPROVIDES:${PN} += "pantavisor-config"
RREPLACES:${PN} += "pantavisor-config"
RCONFLICTS:${PN} += "pantavisor-config"
FILES:${PN} += "${sysconfdir}/pantavisor.config"

PV_CONFIG_SET ??= ""

PV_VARS_FILE = "${STAGING_DATADIR}/pantavisor/pantavisor-vars.env"

pv_config_template_expand() {
	src="$1"
	dst="$2"
	if [ ! -r "${PV_VARS_FILE}" ]; then
		bbfatal "missing ${PV_VARS_FILE} — is 'pantavisor' in DEPENDS?"
	fi
	cp "$src" "$dst.tmp"
	while IFS='=' read -r k v; do
		case "$k" in ''|\#*) continue ;; esac
		# escape sed replacement metachars in the value
		esc=$(printf '%s\n' "$v" | sed 's/[\\&|]/\\&/g')
		sed -i "s|@${k}@|${esc}|g" "$dst.tmp"
	done < "${PV_VARS_FILE}"
	if grep -qE '@[A-Z_][A-Z0-9_]*@' "$dst.tmp"; then
		bbfatal "unsubstituted tokens in $dst.tmp — is pantavisor-vars.env current?"
	fi
	mv "$dst.tmp" "$dst"
}

pv_config_overlay_apply() {
	f="$1"
	for kv in ${PV_CONFIG_SET}; do
		k="${kv%%=*}"
		v="${kv#*=}"
		esc=$(printf '%s\n' "$v" | sed 's/[\\&|]/\\&/g')
		if grep -q "^${k}=" "$f"; then
			sed -i "s|^${k}=.*|${k}=${esc}|" "$f"
		else
			printf '%s=%s\n' "$k" "$v" >> "$f"
		fi
	done
}

do_install() {
	install -d ${D}${sysconfdir}
	out=${D}${sysconfdir}/pantavisor.config

	verbatim="${WORKDIR}/pantavisor.config"
	template="${WORKDIR}/pantavisor.config.in"

	if [ -f "$verbatim" ] && [ -f "$template" ]; then
		bbfatal "ship pantavisor.config OR pantavisor.config.in, not both"
	fi

	if [ -f "$verbatim" ]; then
		install -m 0644 "$verbatim" "$out"
	elif [ -f "$template" ]; then
		pv_config_template_expand "$template" "$out"
	else
		# pantavisor CMake stages a copy of the rendered default at
		# ${datadir}/pantavisor/ for this purpose (Yocto does not stage
		# /etc/* into sysroot).
		base="${STAGING_DATADIR}/pantavisor/pantavisor.config"
		if [ ! -r "$base" ]; then
			bbfatal "no pantavisor.config in sysroot ($base) — is 'pantavisor' in DEPENDS?"
		fi
		install -m 0644 "$base" "$out"
	fi

	pv_config_overlay_apply "$out"
}
