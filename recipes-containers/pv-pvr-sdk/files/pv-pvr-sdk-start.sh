#!/bin/sh

# PID 1 of the container. Replaces the SDK's OpenRC image: one-shots first,
# then the long-running daemons, each in its own respawn loop. The restart
# policy is `system`, so PID 1 exiting reboots the device; a daemon dying must
# therefore never end this script, only restart that daemon.

rm -rf /var/pvr-sdk/tmp/*

# pvcontrol prefers pvcurl, which stages every request in fixed /tmp/http_*
# files, so concurrent calls clobber each other. The CGIs behind httpd hit this
# when pvr fetches objects in parallel (empty objects, "wrong sha"). curl is
# installed, so make pvcontrol use it.
export CURL_CMD=curl

# These two background themselves and return.
/usr/bin/pv-httpd
/usr/bin/pv-socat

# Run "$@" forever. The pause keeps a daemon that fails at once (a bad config,
# a busy port) from spinning; pvr-auto-follow runs under set -e and is expected
# to exit on any failing command, which this turns into a retry.
supervise() {
	(
		while true; do
			"$@"
			echo "pv-pvr-sdk-start: $1 exited ($?), restarting" >&2
			sleep 2
		done
	) &
}

# kill 0 signals the whole process group: the loops and the daemons under them.
trap 'trap "" TERM INT; kill 0; exit 0' TERM INT

supervise /usr/sbin/dropbear -F -E -R -p :22
supervise /usr/bin/pv-user-meta-sync
supervise /usr/bin/pvr-sdk-httpd
supervise /usr/bin/pvr-auto-follow

# Blocks for as long as the loops run, and lets a signal reach the trap.
while true; do
	wait
done
