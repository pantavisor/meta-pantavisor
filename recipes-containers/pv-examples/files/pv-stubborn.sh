#!/bin/sh
#
# pv-stubborn: ignore all catchable signals so LXC has to force-stop (SIGKILL)
# this container. Used to exercise the pv_cgroup_destroy() cleanup path.

# ignore every catchable signal
trap '' TERM PWR INT HUP QUIT USR1 USR2

echo "pv-example-stubborn starting (PID $$) - ignoring all signals..."

while true; do
    sleep 1
done
