#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

# IPAM Test Container
# Displays network configuration and keeps running

echo "=== IPAM Test Container ==="
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo ""
echo "=== Network Interfaces ==="
ip addr show 2>/dev/null || ifconfig -a 2>/dev/null || cat /proc/net/dev
echo ""
echo "=== Routes ==="
ip route show 2>/dev/null || route -n 2>/dev/null || cat /proc/net/route
echo ""
echo "=== Container is running. Sleeping indefinitely. ==="
echo "Press Ctrl+C or stop the container to exit."

# Keep running
while true; do
    sleep 60
done
