#!/bin/sh

export WAYLAND_DISPLAY="wayland-0"
export XDG_RUNTIME_DIR="/run/pv/services"

while true; do
    echo "--- Querying Wayland service via $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ---"
    if [ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
        wayland-info
    else
        echo "Socket not found!"
    fi
    echo -e "\n"
    sleep 5
done
