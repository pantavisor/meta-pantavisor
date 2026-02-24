#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


SOCKET="/run/pv/services/network-manager.sock"

while true; do
    echo "--- Requesting info from network-manager service via $SOCKET ---"
    if [ -S "$SOCKET" ]; then
        curl --unix-socket "$SOCKET" http://localhost/info
    else
        echo "Socket $SOCKET not found!"
    fi
    echo -e "\n"
    sleep 5
done
