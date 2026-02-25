#!/bin/bash
# pv-qemu-tool.sh — QEMU session primitives for AI-driven testing
#
# Provides start/list/wait-shell/exec/wait/log/stop/stop-all subcommands
# for managing QEMU sessions. Each session runs a long-lived expect backend
# (pv-qemu-expect.sh) communicating via named pipes.
#
# Usage: pv-qemu-tool.sh <command> [args...]
#
# Commands:
#   start [--name ID] [--image PATH]  Start QEMU session, print session ID
#   list                               List active sessions
#   wait-shell ID [--timeout S]        Wait for debug shell (default 120s)
#   exec ID "command" [--timeout S]    Run command, print stdout + exit code
#   wait ID "pattern" [--timeout S]    Wait for regex in console (default 60s)
#   log ID [--grep PATTERN]            Dump console log
#   stop ID                            Kill QEMU, cleanup session
#   stop-all                           Kill all sessions
#
# Copyright (c) 2025-2026 Pantacor Ltd.
# SPDX-License-Identifier: MIT

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSIONS_DIR="/tmp/pv-qemu-sessions"
EXPECT_BACKEND="$SCRIPT_DIR/pv-qemu-expect.sh"

BUILDDIR="$TOP_DIR/build"
TMPDIR="$BUILDDIR/tmp-scarthgap"
DEPLOY="$TMPDIR/deploy/images/x64-efi"
DEFAULT_WIC="$DEPLOY/pantavisor-remix-x64-efi.rootfs.wic"
OVMF_VARS="$DEPLOY/ovmf.vars.qcow2"

# --- Helpers ---

die() { echo "ERROR: $*" >&2; exit 1; }

session_dir() {
    local id="$1"
    echo "$SESSIONS_DIR/$id"
}

require_session() {
    local id="$1"
    local dir
    dir="$(session_dir "$id")"
    [ -d "$dir" ] || die "session '$id' not found"
    echo "$dir"
}

# Send a command to the expect backend via FIFO and read the result.
# Usage: fifo_cmd <session_dir> <command_string> [read_timeout]
# read_timeout is a bash read timeout (seconds) — set generously since
# the expect backend has its own internal timeout.
fifo_cmd() {
    local dir="$1" cmd="$2" read_timeout="${3:-300}"
    echo "$cmd" > "$dir/cmd.fifo"
    # Read result (may be multi-line, terminated by a single line)
    local result=""
    local line
    while IFS= read -r -t "$read_timeout" line; do
        if [ "$line" = "END" ]; then
            break
        fi
        if [ -n "$result" ]; then
            result="$result
$line"
        else
            result="$line"
        fi
    done < "$dir/result.fifo"
    echo "$result"
}

# Send a command and read a single-line result.
fifo_cmd_single() {
    local dir="$1" cmd="$2" read_timeout="${3:-300}"
    echo "$cmd" > "$dir/cmd.fifo"
    local line
    IFS= read -r -t "$read_timeout" line < "$dir/result.fifo" || line="TIMEOUT"
    echo "$line"
}

is_session_alive() {
    local dir="$1"
    [ -f "$dir/pid" ] || return 1
    local pid
    pid=$(cat "$dir/pid")
    kill -0 "$pid" 2>/dev/null
}

# --- Commands ---

cmd_start() {
    local name="" image="$DEFAULT_WIC"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name) name="$2"; shift 2 ;;
            --image) image="$2"; shift 2 ;;
            *) die "start: unknown option '$1'" ;;
        esac
    done

    # Generate session ID if not provided
    if [ -z "$name" ]; then
        name="qemu-$(date +%s)-$$"
    fi

    local dir
    dir="$(session_dir "$name")"
    [ -d "$dir" ] && die "session '$name' already exists"

    # Validate image
    [ -f "$image" ] || die "image not found: $image"
    [ -f "$OVMF_VARS" ] || die "OVMF vars not found: $OVMF_VARS"

    # Create session directory and FIFOs
    mkdir -p "$dir"
    mkfifo "$dir/cmd.fifo"
    mkfifo "$dir/result.fifo"

    # Write image path for the expect backend
    echo "$image" > "$dir/image"

    # Writable copy of OVMF vars (persists across reboots within session)
    cp -f "$OVMF_VARS" "$dir/vars.qcow2"

    # Launch expect backend in background
    expect "$EXPECT_BACKEND" "$dir" > "$dir/expect.log" 2>&1 &
    local backend_pid=$!
    echo "$backend_pid" > "$dir/pid"

    # Record start time
    date +%s > "$dir/started"

    echo "$name"
}

cmd_list() {
    [ -d "$SESSIONS_DIR" ] || { echo "No sessions."; return 0; }

    local found=0
    printf "%-20s %-8s %-8s %s\n" "SESSION" "PID" "QEMU" "UPTIME"

    for dir in "$SESSIONS_DIR"/*/; do
        [ -d "$dir" ] || continue
        found=1
        local id
        id=$(basename "$dir")
        local pid="?"
        local qemu_pid="?"
        local uptime="?"
        local status="dead"

        if [ -f "$dir/pid" ]; then
            pid=$(cat "$dir/pid")
            if kill -0 "$pid" 2>/dev/null; then
                status="alive"
            fi
        fi
        if [ -f "$dir/qemu.pid" ]; then
            qemu_pid=$(cat "$dir/qemu.pid")
        fi
        if [ -f "$dir/started" ]; then
            local start_ts
            start_ts=$(cat "$dir/started")
            local now
            now=$(date +%s)
            local elapsed=$(( now - start_ts ))
            uptime="${elapsed}s"
        fi

        printf "%-20s %-8s %-8s %s (%s)\n" "$id" "$pid" "$qemu_pid" "$uptime" "$status"
    done

    if [ "$found" -eq 0 ]; then
        echo "No sessions."
    fi
}

cmd_wait_shell() {
    local id="$1"; shift
    [ -n "$id" ] || die "wait-shell: session ID required"
    local timeout=120

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout="$2"; shift 2 ;;
            *) die "wait-shell: unknown option '$1'" ;;
        esac
    done

    local dir
    dir="$(require_session "$id")"

    local result
    result=$(fifo_cmd_single "$dir" "WAIT_SHELL $timeout" $(( timeout + 30 )))

    if [ "$result" = "OK" ]; then
        echo "OK"
        return 0
    else
        echo "$result"
        return 1
    fi
}

cmd_exec() {
    local id="$1"; shift
    [ -n "$id" ] || die "exec: session ID required"
    local cmd="$1"; shift
    [ -n "$cmd" ] || die "exec: command required"
    local timeout=30

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout="$2"; shift 2 ;;
            *) die "exec: unknown option '$1'" ;;
        esac
    done

    local dir
    dir="$(require_session "$id")"

    local result
    result=$(fifo_cmd "$dir" "EXEC $timeout $cmd" $(( timeout + 30 )))

    # Parse result: first line is EXIT:<code>, rest is output, last line is END
    local exit_line
    exit_line=$(echo "$result" | head -1)
    local exit_code
    exit_code="${exit_line#EXIT:}"

    # Output is everything after the first line
    local output
    output=$(echo "$result" | tail -n +2)

    if [ -n "$output" ]; then
        echo "$output"
    fi

    return "${exit_code:--1}"
}

cmd_wait() {
    local id="$1"; shift
    [ -n "$id" ] || die "wait: session ID required"
    local pattern="$1"; shift
    [ -n "$pattern" ] || die "wait: pattern required"
    local timeout=60

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --timeout) timeout="$2"; shift 2 ;;
            *) die "wait: unknown option '$1'" ;;
        esac
    done

    local dir
    dir="$(require_session "$id")"

    local result
    result=$(fifo_cmd_single "$dir" "WAIT $timeout $pattern" $(( timeout + 30 )))

    if [ "$result" = "OK" ]; then
        echo "OK"
        return 0
    else
        echo "$result"
        return 1
    fi
}

cmd_log() {
    local id="$1"; shift
    [ -n "$id" ] || die "log: session ID required"
    local grep_pattern=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --grep) grep_pattern="$2"; shift 2 ;;
            *) die "log: unknown option '$1'" ;;
        esac
    done

    local dir
    dir="$(require_session "$id")"
    local logfile="$dir/console.log"

    if [ ! -f "$logfile" ]; then
        echo "(no console output yet)"
        return 0
    fi

    if [ -n "$grep_pattern" ]; then
        grep -E "$grep_pattern" "$logfile" || true
    else
        cat "$logfile"
    fi
}

cmd_stop() {
    local id="$1"
    [ -n "$id" ] || die "stop: session ID required"

    local dir
    dir="$(require_session "$id")"

    if is_session_alive "$dir"; then
        # Try graceful shutdown via FIFO
        echo "QUIT" > "$dir/cmd.fifo" 2>/dev/null || true
        local pid
        pid=$(cat "$dir/pid")
        # Wait briefly for graceful exit
        local i=0
        while [ $i -lt 10 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.5
            i=$(( i + 1 ))
        done
        # Force kill if still alive
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    # Also kill QEMU directly if still running
    if [ -f "$dir/qemu.pid" ]; then
        local qpid
        qpid=$(cat "$dir/qemu.pid")
        kill -9 "$qpid" 2>/dev/null || true
    fi

    rm -rf "$dir"
    echo "Session '$id' stopped."
}

cmd_stop_all() {
    [ -d "$SESSIONS_DIR" ] || { echo "No sessions."; return 0; }

    for dir in "$SESSIONS_DIR"/*/; do
        [ -d "$dir" ] || continue
        local id
        id=$(basename "$dir")
        cmd_stop "$id"
    done
}

# --- Main dispatch ---

usage() {
    cat <<'EOF'
Usage: pv-qemu-tool.sh <command> [args...]

Commands:
  start [--name ID] [--image PATH]  Start QEMU session, print session ID
  list                               List active sessions
  wait-shell ID [--timeout S]        Wait for debug shell (default 120s)
  exec ID "command" [--timeout S]    Run command in guest (default 30s)
  wait ID "pattern" [--timeout S]    Wait for regex in console (default 60s)
  log ID [--grep PATTERN]            Dump console log
  stop ID                            Kill QEMU, cleanup session
  stop-all                           Kill all sessions
EOF
}

command="${1:-}"
shift || true

case "$command" in
    start)      cmd_start "$@" ;;
    list)       cmd_list "$@" ;;
    wait-shell) cmd_wait_shell "$@" ;;
    exec)       cmd_exec "$@" ;;
    wait)       cmd_wait "$@" ;;
    log)        cmd_log "$@" ;;
    stop)       cmd_stop "$@" ;;
    stop-all)   cmd_stop_all "$@" ;;
    -h|--help|help|"")  usage ;;
    *)          die "unknown command '$command'" ;;
esac
