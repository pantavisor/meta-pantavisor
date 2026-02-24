#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


SOCKET="/run/pv/services/raw-unix.sock"

while true; do
    echo "--- Sending data to raw Unix service via $SOCKET ---"
    if [ -S "$SOCKET" ]; then
        echo "Hello from client at $(date)" | socat - UNIX-CONNECT:$SOCKET
    else
        echo "Socket $SOCKET not found!"
    fi
    echo -e "\n"
    sleep 5
done

