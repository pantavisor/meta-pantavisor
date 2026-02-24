#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


# Socket is injected at /run/wayland-0 by pv-xconnect
export WAYLAND_DISPLAY="/run/wayland-0"

MAX_RETRIES=30
RETRY=0

echo "Waiting for Wayland socket at $WAYLAND_DISPLAY..."

while [ $RETRY -lt $MAX_RETRIES ]; do
    if [ -S "$WAYLAND_DISPLAY" ]; then
        echo "SUCCESS: Found Wayland socket"
        ls -la "$WAYLAND_DISPLAY"
        echo ""
        echo "--- Querying Wayland compositor ---"
        wayland-info 2>&1 || echo "wayland-info failed (may need fd passing support)"
        sleep infinity
    fi
    RETRY=$((RETRY + 1))
    sleep 1
done

echo "FAILED: Wayland socket not found after $MAX_RETRIES seconds"
exit 1
