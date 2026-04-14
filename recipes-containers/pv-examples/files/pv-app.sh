#!/bin/sh

trap 'echo "Received shutdown signal, exiting..."; exit 0' TERM PWR INT

echo "pv-example-app starting (PID $$)..."

while true; do
    sleep 1
done
