#!/bin/sh

trap 'echo "Received SIGTERM, exiting..."; exit 0' TERM

echo "pv-example-app starting (PID $$)..."

while true; do
    sleep 1
done
