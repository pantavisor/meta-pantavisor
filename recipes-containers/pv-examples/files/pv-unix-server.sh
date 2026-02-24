#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT


SOCKET="/run/example/raw.sock"
mkdir -p $(dirname $SOCKET)
rm -f $SOCKET

echo "Starting raw Unix socket server on $SOCKET..."
# Use socat to echo back whatever is received
socat UNIX-LISTEN:$SOCKET,fork EXEC:/bin/cat