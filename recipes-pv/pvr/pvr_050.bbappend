# Workaround for a pvr 050 template bug that produces invalid run.json
# when a container declares two or more volumes via PV_VOLUME_MOUNTS.
#
# templates/builtin-lxc-docker.go contains:
#     {{ join ",\\n" $n }}
# which emits a literal `\n` in the JSON volumes array, e.g.:
#     "volumes":[ "a.squashfs",\n"b.squashfs" ]
# Single-volume builds work by accident (join skips the separator).
#
# Fix at unpack time so the compiled pvr binary uses a plain comma.
# Drop this bbappend once the upstream pvr release ships the fix.
do_compile:prepend() {
    sed -i 's|{{ join ",\\\\n" $n }}|{{ join "," $n }}|' \
        ${S}/src/${GO_IMPORT}/templates/builtin-lxc-docker.go
}
