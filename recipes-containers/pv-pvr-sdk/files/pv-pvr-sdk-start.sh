#!/bin/sh

# PID 1 of the container. Replaces the SDK's OpenRC image: one-shots first,
# then the long-running daemons. If any daemon dies the script exits, and
# Pantavisor restarts the whole container (PV_RESTART_POLICY=system).

rm -rf /var/pvr-sdk/tmp/*

# pvcontrol prefers pvcurl, which stages every request in fixed /tmp/http_*
# files, so concurrent calls clobber each other. The CGIs behind httpd hit this
# when pvr fetches objects in parallel (empty objects, "wrong sha"). curl is
# installed, so make pvcontrol use it.
export CURL_CMD=curl

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
start /usr/bin/pvr-sdk-httpd

# pvr-auto-follow runs under set -e and exits on any failing command. Under
# OpenRC that was a logged service failure; watched directly it would stop the
# container and reboot the device (restart policy system). So the retry loop is
# what gets watched, not the script.
(
	while true; do
		/usr/bin/pvr-auto-follow
		sleep 30
	done
) &
pids="$pids $!"

while true; do
	for pid in $pids; do
		if ! kill -0 "$pid" 2>/dev/null; then
			echo "pv-pvr-sdk-start: pid $pid exited, stopping container" >&2
			stop_all
		fi
	done
	sleep 2
done
