#!/bin/sh

# We use busctl or dbus-send if available
while true; do
    echo "--- Requesting info from D-Bus service org.pantavisor.Example ---"
    busctl call org.pantavisor.Example /org/pantavisor/Example org.pantavisor.Example GetInfo
    echo -e "\n"
    sleep 5
done
