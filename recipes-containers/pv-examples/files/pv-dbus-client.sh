#!/bin/sh

while true; do
    echo "--- Requesting info from D-Bus service org.pantavisor.Example ---"
    if command -v busctl >/dev/null 2>&1; then
        busctl call org.pantavisor.Example /org/pantavisor/Example org.pantavisor.Example GetInfo
    elif command -v dbus-send >/dev/null 2>&1; then
        dbus-send --system --print-reply --dest=org.pantavisor.Example /org/pantavisor/Example org.pantavisor.Example.GetInfo
    else
        echo "Neither busctl nor dbus-send found!"
    fi
    echo -e "\n"
    sleep 5
done
