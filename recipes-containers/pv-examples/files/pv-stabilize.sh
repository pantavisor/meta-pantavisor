#!/bin/sh
STATE_FILE="/var/lib/boot_count"
mkdir -p /var/lib

if [ ! -f "$STATE_FILE" ]; then
    echo "0" > "$STATE_FILE"
fi

COUNT=$(cat "$STATE_FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$STATE_FILE"

echo "Stabilize test container starting... (Run #$COUNT)"
echo "Uptime: $(cat /proc/uptime)"

if [ "$COUNT" -le 3 ]; then
    echo "I am in the failing phase. Sleeping 5s and exiting with error."
    sleep 5
    exit 1
else
    echo "I have reached the stable phase! Sleeping infinity..."
    sleep infinity
fi
