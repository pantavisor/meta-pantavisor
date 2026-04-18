#!/bin/sh

# Stage writable copies of avahi config into /tmp (which has an overlay volume).
# /etc lives on the read-only squashfs lower, so we never sed it in place.
RUNDIR=/tmp/avahi-run
CONF=$RUNDIR/avahi-daemon.conf
SVCDIR=$RUNDIR/services

mkdir -p "$RUNDIR" "$SVCDIR"
cp /etc/avahi/avahi-daemon.conf "$CONF"
cp /etc/avahi/services/ssh.service "$SVCDIR/ssh.service"
sed -i "s|^services-dir=.*|services-dir=$SVCDIR|" "$CONF" 2>/dev/null || \
	echo "services-dir=$SVCDIR" >> "$CONF"

hostname=pantavisor
if [ -e /pantavisor/device-nick ]; then
	hostname=$(cat /pantavisor/device-nick | xargs 2>/dev/null)
fi
sed -i "s/^host-name=.*/host-name=$hostname/" "$CONF"

devnet=
if [ -e /pantavisor/device-net ]; then
	devnet=$(cat /pantavisor/device-net | xargs 2>/dev/null)
fi
localdomain=${devnet:-local}
sed -i "s/^domain-name=.*/domain-name=$localdomain/" "$CONF"

deviceid=
if [ -e /pantavisor/device-id ]; then
	deviceid=$(cat /pantavisor/device-id | xargs 2>/dev/null)
fi
challenge=
if [ -e /pantavisor/challenge ]; then
	challenge=$(cat /pantavisor/challenge | xargs 2>/dev/null)
fi
phurl=
if [ -e /pantavisor/pantahub-host ]; then
	phurl=$(cat /pantavisor/pantahub-host | xargs 2>/dev/null)
fi

if [ -n "$deviceid" ] || [ -n "$challenge" ] || [ -n "$phurl" ]; then
	sed -i '/<txt-record>/d' "$SVCDIR/ssh.service"
	sed -i '/<subtype>/d' "$SVCDIR/ssh.service"
	sed -i '/<type>/a <subtype>_pantavisor._sub._ssh._tcp</subtype>' "$SVCDIR/ssh.service"
	if [ -n "$deviceid" ]; then
		sed -i "/<port>/a <txt-record>device-id=$deviceid</txt-record>" "$SVCDIR/ssh.service"
	fi
	if [ -n "$challenge" ]; then
		sed -i "/<port>/a <txt-record>challenge=$challenge</txt-record>" "$SVCDIR/ssh.service"
	fi
	if [ -n "$phurl" ]; then
		sed -i "/<port>/a <txt-record>pantahub=$phurl</txt-record>" "$SVCDIR/ssh.service"
	fi
fi

exec avahi-daemon -f "$CONF"
