#!/bin/sh

trap 'echo "Received shutdown signal, exiting..."; exit 0' TERM PWR INT

echo "pv-example-ready-timeout starting (PID $$)..."

# Never send the READY signal: with status_goal READY this deterministically
# times out the update goals and triggers a rollback. Counterpart of
# pv-example-ready, which signals as soon as it is up.
while true; do
    sleep 1
done
