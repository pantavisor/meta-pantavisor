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
echo "pv-avahi-browse: hosted D-Bus system bus at $DBUS_SOCKET -> browsing via org.freedesktop.Avahi"

while true; do
	echo "--- avahi-browse: all services (resolved) ---"
	avahi-browse -atrp 2>&1 || echo "pv-avahi-browse: avahi-browse failed"
	sleep 10
done
