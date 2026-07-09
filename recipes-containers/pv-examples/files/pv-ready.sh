#!/bin/sh

trap 'echo "Received shutdown signal, exiting..."; exit 0' TERM PWR INT

echo "pv-example-ready starting (PID $$)..."

# Signal READY as soon as the pv-ctrl socket answers; with status_goal READY
# this lets the update meet its goals. Counterpart of pv-example-ready-timeout,
# which never signals.
until pvcontrol signal ready > /dev/null 2>&1; do
    sleep 1
done
echo "pv-example-ready: READY signal sent"

while true; do
    sleep 1
done
