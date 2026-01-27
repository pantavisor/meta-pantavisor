#!/bin/sh

# Set up runtime directory for Weston
export XDG_RUNTIME_DIR=/run
mkdir -p $XDG_RUNTIME_DIR

# Wait for DRM device
MAX_RETRIES=30
RETRY=0

echo "Waiting for DRM device..."

while [ $RETRY -lt $MAX_RETRIES ]; do
    if [ -e /dev/dri/card0 ]; then
        echo "Found DRM device:"
        ls -la /dev/dri/
        break
    fi
    RETRY=$((RETRY + 1))
    sleep 1
done

if [ ! -e /dev/dri/card0 ]; then
    echo "ERROR: DRM device not found after $MAX_RETRIES seconds"
    exit 1
fi

echo "Starting Weston compositor..."
exec weston --backend=drm-backend.so --socket=wayland-0 --log=/tmp/weston.log 2>&1
