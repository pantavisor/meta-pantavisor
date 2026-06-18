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

# Decide whether to expose avahi's D-Bus API on the pantavisor-hosted system
# bus. The bus socket is injected by xconnect (asynchronously), so we wait a
# short grace period before deciding.
#
#   - socket present       -> enable-dbus=yes (expose org.freedesktop.Avahi)
#   - socket absent        -> enable-dbus=no  (plain mDNS, graceful degrade)
#   - PV_AVAHI_REQUIRE_DBUS=1 and socket absent -> exit non-zero so a mis-wired
#     stack (bus feature off, missing requirement, etc.) fails and rolls back.
#
# avahi is the container's PID 1 (we exec it below, no init wrapper), so this
# non-zero exit becomes the container exit status that pantavisor acts on.
DBUS_SOCKET=/run/dbus/system_bus_socket

# xconnect injects the bus socket only after it has reconciled the link graph,
# which can take well over the container's first few seconds. Wait generously so
# we don't lose the D-Bus API to a startup race; the socket, once present, stays.
DBUS_WAIT=${PV_AVAHI_DBUS_WAIT:-60}

i=0
while [ ! -S "$DBUS_SOCKET" ] && [ "$i" -lt "$DBUS_WAIT" ]; do
	i=$((i + 1))
	sleep 1
done

if [ -S "$DBUS_SOCKET" ]; then
	echo "pv-avahi: hosted D-Bus system bus at $DBUS_SOCKET after ${i}s -> enabling D-Bus API (org.freedesktop.Avahi)"
	sed -i 's/^enable-dbus=.*/enable-dbus=yes/' "$CONF"
elif [ "${PV_AVAHI_REQUIRE_DBUS:-0}" = "1" ]; then
	echo "pv-avahi: PV_AVAHI_REQUIRE_DBUS=1 but $DBUS_SOCKET absent after ${DBUS_WAIT}s -> failing for rollback" >&2
	exit 1
else
	echo "pv-avahi: no D-Bus system bus at $DBUS_SOCKET -> starting plain mDNS without D-Bus API"
	sed -i 's/^enable-dbus=.*/enable-dbus=no/' "$CONF"
fi

exec avahi-daemon -f "$CONF"
