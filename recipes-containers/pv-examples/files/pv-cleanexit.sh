#!/bin/sh
echo "Clean exit test container starting..."
echo "Uptime: $(cat /proc/uptime)"

echo "I will sleep for 5 seconds and then exit cleanly (0)."
sleep 5
echo "Exiting cleanly now!"
exit 0
