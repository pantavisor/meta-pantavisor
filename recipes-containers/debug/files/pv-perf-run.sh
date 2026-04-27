#!/bin/sh
# pv-perf entrypoint — keep the container alive so an operator can
# pventer into it and run perf against pantavisor.
#
# The container is configured (see pv-perf.args.json) to keep the host
# PID / net / IPC / UTS namespaces, so PIDs inside this container
# match the host's.
#
# Note: PID 1 on the host is the pantavisor supervisor and is mostly
# sleeping. The hot worker is `pv-main-loop`, a child process. Profile
# it by name or by looking up its pid:
#
#   pid=$(pidof pv-main-loop)
#   perf top -p "$pid"
#   perf record -F 99 -p "$pid" -g -- sleep 20 && perf report
#
# To profile *all* pantavisor-side workers (pv-main-loop +
# pv-platform-* + pv-logger-* + pv-xconnect-out):
#
#   perf top --comm pantavisor,pv-main-loop,pv-xconnect-out
#
# We don't run perf at boot — that would be a continuous attach. The
# operator drives it interactively.

set -eu

log() { printf '%s pv-perf: %s\n' "$(date -Iseconds)" "$*" >&2; }

log "started; $(perf --version 2>/dev/null || echo 'perf missing')"
main_pid=$(pidof pv-main-loop 2>/dev/null || true)
if [ -n "$main_pid" ]; then
    log "pv-main-loop is host pid $main_pid"
    log "  perf top -p $main_pid"
    log "  perf record -F 99 -p $main_pid -g -- sleep 20 && perf report"
else
    log "pv-main-loop not yet visible from this namespace"
fi

# Keep the container alive forever; LXC wants this pid (which is
# *not* host pid 1 — we kept the host PID namespace, but exec'd a
# fresh process under it) to stay around.
exec sleep infinity
