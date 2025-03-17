FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://pv_env_fragment.txt \
"

do_deploy:append() {
    base_env="${B}/u-boot-initial-env"

    if [ -f "$base_env" ]; then
        cat "$base_env" "${WORKDIR}/pv_env_fragment.txt" > "${WORKDIR}/u-boot-initial-env.final"
        install -D -m 644 "${WORKDIR}/u-boot-initial-env.final" "${DEPLOYDIR}/u-boot-initial-env"
    else
        echo "WARNING: u-boot-initial-env not found in ${B}" >&2
    fi
}
