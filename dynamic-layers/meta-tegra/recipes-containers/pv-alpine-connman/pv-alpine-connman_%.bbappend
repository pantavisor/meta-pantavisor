# The os inittab respawns busybox syslogd, which cannot bind the /dev/log
# pantavisor mounts in and floods the console with "bind: Address in use"
# every second. Let syslogd own /dev/log inside the container instead.
do_compile:prepend:tegra210() {
	jq '. + { "dev-log": false }' ${PVCONT_NAME}/run.json > ${PVCONT_NAME}/run.json.new
	mv -f ${PVCONT_NAME}/run.json.new ${PVCONT_NAME}/run.json
}
