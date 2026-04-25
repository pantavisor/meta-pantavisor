#!/bin/sh
# Launcher for the on-device DeepSeek model served by llama-server.
#
# The GGUF is baked into the image (see the recipe's SRC_URI), so this
# script does nothing but sanity-check the model file, start a socat
# bridge exposing the HTTP API on a UDS (so xconnect can proxy it as a
# 'rest' service), and exec llama-server on TCP.
#
# Env overrides (all have sensible defaults):
#   DEEPSEEK_MODEL_PATH  on-disk path to the GGUF (set by the recipe)
#   DEEPSEEK_PORT        TCP port for the HTTP API (default 8080)
#   DEEPSEEK_UDS         UDS path bridged to the TCP API (default
#                        /run/deepseek-r1/api.sock) — matches the
#                        xconnect service manifest
#   DEEPSEEK_CTX         context size (default 4096)
#   DEEPSEEK_THREADS     inference threads (default: all cores)
#   DEEPSEEK_EXTRA       extra args appended verbatim to llama-server

set -eu

: "${DEEPSEEK_MODEL_PATH:=/usr/share/pv-llama-deepseek-r1/deepseek.gguf}"
: "${DEEPSEEK_PORT:=8080}"
: "${DEEPSEEK_UDS:=/run/deepseek-r1/api.sock}"
: "${DEEPSEEK_CTX:=4096}"
: "${DEEPSEEK_THREADS:=$(nproc 2>/dev/null || echo 2)}"
: "${DEEPSEEK_EXTRA:=}"

log() {
    printf '%s deepseek: %s\n' "$(date -Iseconds)" "$*" >&2
}

if [ ! -s "$DEEPSEEK_MODEL_PATH" ]; then
    log "FATAL: model missing at $DEEPSEEK_MODEL_PATH"
    exit 1
fi

# Start the UDS → TCP bridge before llama-server; socat will simply
# retry-reconnect on each accepted connection until llama-server is up.
# xconnect mediates this UDS and injects a proxied socket into consumers
# under /run/pv/services/deepseek-r1.sock.
mkdir -p "$(dirname "$DEEPSEEK_UDS")"
rm -f "$DEEPSEEK_UDS"
log "bridging $DEEPSEEK_UDS -> 127.0.0.1:$DEEPSEEK_PORT (socat)"
socat "UNIX-LISTEN:$DEEPSEEK_UDS,fork,reuseaddr,mode=0660" \
      "TCP:127.0.0.1:$DEEPSEEK_PORT" &
SOCAT_PID=$!
trap 'kill $SOCAT_PID 2>/dev/null || true' EXIT INT TERM

log "starting llama-server on :$DEEPSEEK_PORT (ctx=$DEEPSEEK_CTX threads=$DEEPSEEK_THREADS)"
# shellcheck disable=SC2086
exec llama-server \
    --model "$DEEPSEEK_MODEL_PATH" \
    --host 0.0.0.0 \
    --port "$DEEPSEEK_PORT" \
    --ctx-size "$DEEPSEEK_CTX" \
    --threads "$DEEPSEEK_THREADS" \
    --jinja \
    $DEEPSEEK_EXTRA
