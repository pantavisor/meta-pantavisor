#!/bin/sh

# PID 1 of the container. Replaces the SDK's OpenRC image: one-shots first,
# then the long-running daemons. If any daemon dies the script exits, and
# Pantavisor restarts the whole container (PV_RESTART_POLICY=system).

rm -rf /var/pvr-sdk/tmp/*

# These two background themselves and return.
/usr/bin/pv-httpd
/usr/bin/pv-socat

pids=""
start() {
	"$@" &
	pids="$pids $!"
}

stop_all() {
	# shellcheck disable=SC2086
	kill $pids 2>/dev/null
	exit 0
}
trap stop_all TERM INT

start /usr/sbin/dropbear -F -E -R -p :22
start /usr/bin/pv-user-meta-sync
start /usr/bin/pvr-auto-follow
start /usr/bin/pvr-sdk-httpd

while true; do
	for pid in $pids; do
		if ! kill -0 "$pid" 2>/dev/null; then
			echo "pv-pvr-sdk-start: pid $pid exited, stopping container" >&2
			stop_all
		fi
	done
	sleep 2
done
