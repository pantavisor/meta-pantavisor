#!/bin/sh
#
# Simple network client for IPAM testing
# Periodically queries the network server
#

SERVER_HOST="${NET_SERVER_HOST:-net-server}"
SERVER_PORT="${NET_SERVER_PORT:-8080}"
INTERVAL="${POLL_INTERVAL:-10}"

echo "IPAM Network Test Client"
echo "========================"
echo "Server: ${SERVER_HOST}:${SERVER_PORT}"
echo "Interval: ${INTERVAL}s"
echo ""

# Wait for network to be ready
sleep 5

while true; do
    echo "[$(date)] Querying server..."

    # Try to resolve and connect
    if curl -s --max-time 5 "http://${SERVER_HOST}:${SERVER_PORT}/info"; then
        echo ""
        echo "[$(date)] Success!"
    else
        echo "[$(date)] Failed to connect to ${SERVER_HOST}:${SERVER_PORT}"

        # Show our network info for debugging
        echo "Local interfaces:"
        ip addr 2>/dev/null || ifconfig 2>/dev/null || echo "(no ip/ifconfig available)"
        echo ""

        # Try to resolve the hostname
        echo "DNS lookup for ${SERVER_HOST}:"
        nslookup ${SERVER_HOST} 2>/dev/null || getent hosts ${SERVER_HOST} 2>/dev/null || echo "(lookup failed)"
        echo ""
    fi

    sleep ${INTERVAL}
done
