#!/bin/sh
# pv-example-svc-tcp-provider — minimal HTTP backend for xconnect Tier-1 testing.
# Uses `nc -l 80` in a loop because the appengine busybox doesn't have the
# httpd applet enabled. ClusterIP routing + DNAT is provided by pv-xconnect
# on the consumer side; we just bind on TCP/80 in our own netns.
set -u

BODY="hello-tcp v1"
LEN=$(printf '%s' "$BODY" | wc -c)
RESP=$(printf 'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$LEN" "$BODY")

while :; do
    # netcat-openbsd: -l listen, -p port, -q 1 close 1s after EOF.
    printf '%s' "$RESP" | nc -l -p 80 -q 1 >/dev/null 2>&1 || true
done
