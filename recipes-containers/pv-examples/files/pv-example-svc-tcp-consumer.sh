#!/bin/sh
# pv-example-svc-tcp-consumer — exercises Tier-1 ClusterIP+DNS resolution.
# Resolves hello-tcp.pv.local (injected into /etc/hosts by pv-xconnect),
# fetches its index, stamps each attempt under /storage/test-results/.
# Loops forever so a watcher can poll across container restarts.
set -u

OUT=/storage/test-results
mkdir -p "$OUT"
LOG="$OUT/tcp-consumer.log"

resolve() {
    # Look in /etc/hosts first (xconnect-injected); fall back to nslookup.
    awk '$2 == "hello-tcp.pv.local" || $3 == "hello-tcp.pv.local" {print $1; exit}' /etc/hosts \
        || nslookup hello-tcp.pv.local 2>/dev/null | awk '/Address: / {print $2; exit}'
}

while :; do
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    ip=$(resolve)
    if [ -n "$ip" ] && body=$(wget -q -T 5 -O - "http://hello-tcp.pv.local/" 2>/dev/null); then
        printf '%s ok ip=%s body=%s\n' "$ts" "$ip" "$body" >> "$LOG"
    else
        printf '%s FAIL ip=%s\n' "$ts" "${ip:-unresolved}" >> "$LOG"
    fi
    sleep 5
done
