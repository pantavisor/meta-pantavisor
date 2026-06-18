#!/bin/sh

# Stage a writable copy of avahi's config in /tmp (the squashfs lower is
# read-only; we point avahi at it with -f). The static *service* file, however,
# must live in avahi's compiled-in services directory — /etc/avahi/services —
# because "services-dir" is NOT a valid avahi-daemon.conf key (avahi rejects the
# config and exits if it is present) and avahi reads service files only from
# that path. /etc/avahi/services is writable here via the container overlay.
RUNDIR=/tmp/avahi-run
CONF=$RUNDIR/avahi-daemon.conf
TEMPLATE=$RUNDIR/ssh.service.tmpl
SVCFILE=/etc/avahi/services/ssh.service

mkdir -p "$RUNDIR"
cp /etc/avahi/avahi-daemon.conf "$CONF"
cp "$SVCFILE" "$TEMPLATE"   # keep a pristine copy before we start rewriting it

# Read the first line of $1, trimmed, into the variable named $2 (empty if the
# file is missing/empty). Uses the shell builtin `read` rather than `cat|xargs`:
# this busybox has no xargs applet, so the old pipeline silently yielded "".
read_meta_field() {
	eval "$2=''"
	[ -r "$1" ] && read -r "$2" < "$1"
	return 0
}

read_meta_field /pantavisor/device-nick hostname
[ -n "$hostname" ] || hostname=pantavisor
sed -i "s/^host-name=.*/host-name=$hostname/" "$CONF"

read_meta_field /pantavisor/device-net devnet
localdomain=${devnet:-local}
sed -i "s/^domain-name=.*/domain-name=$localdomain/" "$CONF"

read_meta() {
	read_meta_field /pantavisor/device-id deviceid
	read_meta_field /pantavisor/challenge challenge
	read_meta_field /pantavisor/pantahub-host phurl
}

# Rebuild the service file from the pristine template each time, so cleared
# fields (e.g. challenge after claim) don't linger.
write_service() {
	cp "$TEMPLATE" "$SVCFILE"
	if [ -n "$deviceid" ] || [ -n "$challenge" ] || [ -n "$phurl" ]; then
		sed -i '/<type>/a <subtype>_pantavisor._sub._ssh._tcp</subtype>' "$SVCFILE"
		if [ -n "$deviceid" ]; then
			sed -i "/<port>/a <txt-record>device-id=$deviceid</txt-record>" "$SVCFILE"
		fi
		if [ -n "$challenge" ]; then
			sed -i "/<port>/a <txt-record>challenge=$challenge</txt-record>" "$SVCFILE"
		fi
		if [ -n "$phurl" ]; then
			sed -i "/<port>/a <txt-record>pantahub=$phurl</txt-record>" "$SVCFILE"
		fi
	fi
}

read_meta
write_service

avahi-daemon -f "$CONF" &
apid=$!

# device-id/challenge are written by Pantavisor asynchronously (after the device
# registers with pantahub), which can happen long after this container started
# (e.g. only once Wi-Fi is provisioned). Re-publish on change instead of
# snapshotting once at boot.
# ponytail: 5s poll; switch to inotify on /pantavisor only if this proves too slow.
last="$deviceid|$challenge|$phurl"
while kill -0 "$apid" 2>/dev/null; do
	sleep 5
	read_meta
	cur="$deviceid|$challenge|$phurl"
	if [ "$cur" != "$last" ]; then
		write_service
		# avahi does NOT reload static services on SIGHUP in this build, so
		# restart the daemon to re-read /etc/avahi/services (matches upstream
		# pv-avahid, which does `rc-service avahi-daemon restart` on change).
		kill "$apid" 2>/dev/null
		wait "$apid" 2>/dev/null
		avahi-daemon -f "$CONF" &
		apid=$!
		last="$cur"
	fi
done
wait "$apid"
