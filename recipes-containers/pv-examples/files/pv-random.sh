#!/bin/sh
echo "Random restart container starting..."
echo "Uptime: $(cat /proc/uptime)"

# Generate a random sleep time between 10 and 30 seconds
SLEEP_TIME=$(( $(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 21 + 10 ))

echo "I will sleep for $SLEEP_TIME seconds and then exit with failure (1)."
sleep $SLEEP_TIME
echo "Exiting now!"
exit 1
