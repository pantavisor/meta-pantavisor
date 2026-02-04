#!/bin/sh
# Simple DRM render test - checks for /dev/dri/renderD128
echo "DRM Render Container starting..."

DEVICE="/dev/dri/renderD128"
MAX_RETRIES=30
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    if [ -e "$DEVICE" ]; then
        echo "SUCCESS: Found $DEVICE"
        ls -la "$DEVICE"
        # Keep running to keep container alive
        echo "Container alive, sleeping..."
        sleep infinity
    fi
    echo "Waiting for $DEVICE (attempt $RETRY/$MAX_RETRIES)..."
    sleep 1
    RETRY=$((RETRY + 1))
done

echo "FAILED: $DEVICE not found after $MAX_RETRIES attempts"
exit 1
