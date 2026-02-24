#!/bin/sh

# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

echo "Recovery test container starting..."
echo "Uptime: $(cat /proc/uptime)"
echo "I will sleep for 10 seconds and then exit with failure (1)."
sleep 10
echo "Exiting now!"
exit 1
