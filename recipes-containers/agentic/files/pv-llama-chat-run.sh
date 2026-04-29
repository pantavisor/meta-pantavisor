#!/bin/sh
# pv-llama-chat container entrypoint.
set -eu

# Pull port + UDS from the env file generated at build time so the
# image config stays declarative (recipe variable → file, not script
# string-substitution).
. /etc/pv-llama-chat/env

exec python3 /usr/lib/pv-llama-chat/server.py \
    --port "${PV_LLAMA_CHAT_PORT:-8080}" \
    --uds  "${PV_LLAMA_UDS:-/run/pv/services/pv-llama.sock}" \
    --www  /usr/lib/pv-llama-chat
