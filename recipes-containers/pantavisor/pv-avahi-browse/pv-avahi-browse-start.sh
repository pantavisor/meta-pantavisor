#!/bin/sh

# pv-avahi-browse: consume avahi's mDNS D-Bus API over the pantavisor-hosted
# system bus *when it is available*, otherwise idle.
#
# The browse/resolve API is reached entirely over D-Bus (avahi-client), so with
# no hosted bus there is simply nothing to talk to. Mirroring the avahi owner
# container, we therefore use D-Bus only if xconnect has injected the bus
# socket; if it is absent we log that and idle instead of flapping.
DBUS_SOCKET=/run/dbus/system_bus_socket
DBUS_WAIT=${PV_AVAHI_DBUS_WAIT:-5}

# Auto-browse can be disabled per-device via the usermeta key
# `pv-avahi-browse.autostart` (see docs/reference/pantavisor-metadata.md). Any
# value of "0" disables the loop below so on-demand activation can instead be
# demonstrated by execing into this container and running an avahi D-Bus
# command by hand. Absent (the default) or any other value keeps today's
# behavior: browse automatically.
#
# This container carries the `mgmt` role, so it gets the *general*
# /pantavisor/user-meta mount (one file per full key, e.g.
# pv-avahi-browse.autostart) rather than the per-platform-scoped mount
# (plugins/pv_lxc.c: PLAT_ROLE_MGMT branch vs the else branch) that a plain
# `app`-only container would get, where the file would instead be the
# platform-stripped `autostart`. Check both so this keeps working if the role
# ever changes.
AUTOSTART=1
for AUTOSTART_FILE in /pantavisor/user-meta/pv-avahi-browse.autostart \
		      /pantavisor/user-meta/autostart; do
	[ -r "$AUTOSTART_FILE" ] && read -r AUTOSTART < "$AUTOSTART_FILE" && break
done

i=0
while [ ! -S "$DBUS_SOCKET" ] && [ "$i" -lt "$DBUS_WAIT" ]; do
	i=$((i + 1))
	sleep 1
done

if [ ! -S "$DBUS_SOCKET" ]; then
	echo "pv-avahi-browse: no D-Bus system bus at $DBUS_SOCKET -> idling (nothing to browse)"
	while true; do sleep 3600; done
fi

export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$DBUS_SOCKET"
echo "pv-avahi-browse: hosted D-Bus system bus at $DBUS_SOCKET"

if [ "$AUTOSTART" = "0" ]; then
	echo "pv-avahi-browse: pv-avahi-browse.autostart=0 -> idling; exec in and run e.g. 'avahi-browse -atrp' to trigger on-demand activation manually"
	while true; do sleep 3600; done
fi

echo "pv-avahi-browse: browsing via org.freedesktop.Avahi"

while true; do
	echo "--- avahi-browse: all services (resolved) ---"
	avahi-browse -atrp 2>&1 || echo "pv-avahi-browse: avahi-browse failed"
	sleep 10
done
