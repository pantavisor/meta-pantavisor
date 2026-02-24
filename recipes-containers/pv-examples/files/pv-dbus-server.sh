#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


# Create dbus directory and uuid
mkdir -p /var/lib/dbus
dbus-uuidgen --ensure

# Start dbus-daemon
mkdir -p /run/dbus
rm -f /run/dbus/system_bus_socket
dbus-daemon --system --nofork --nopidfile &

# Wait for socket
while [ ! -S /run/dbus/system_bus_socket ]; do
    sleep 1
done

# Start the python service
exec /usr/bin/pv-dbus-server.py
