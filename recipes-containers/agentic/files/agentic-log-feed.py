#!/usr/bin/env python3
"""
Agentic log-feed

Runs as a mgmt-role container (PV_ROLES=["mgmt"] in args.json), so
Pantavisor bind-mounts the consolidated log tree at
/pantavisor/logs/current/<container>/<source>. This daemon walks that
tree, tails every file (filetree output format), matches ERROR / FATAL /
CRITICAL lines, and republishes them with surrounding context as NDJSON
over HTTP chunked transfer on a UDS.

Endpoints:
  GET /info       -> JSON describing the feed config
  GET /subscribe  -> chunked NDJSON stream of error events

Env overrides:
  LOG_ROOT         root of the per-container log tree
                   (default: /pantavisor/logs/current)
  LOG_SINGLE_PATH  if set, ignore LOG_ROOT and tail this single file only
                   (useful for appengine / dev without mgmt role)
  LOG_PATTERN      regex (default matches ERROR / ERR / FATAL / CRITICAL)
  LOG_CONTEXT_PRE  lines of pre-context (default 3)
  LOG_CONTEXT_POST lines of post-context (default 3)
  LOG_SCAN_INTERVAL seconds between directory rescans (default 5)
"""

import json
import os
import re
import socket
import sys
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_ROOT = os.environ.get("LOG_ROOT", "/pantavisor/logs/current")
LOG_SINGLE_PATH = os.environ.get("LOG_SINGLE_PATH", "")
LOG_PATTERN = os.environ.get("LOG_PATTERN", r"\b(ERROR|ERR|FATAL|CRITICAL)\b")
LOG_CONTEXT_PRE = int(os.environ.get("LOG_CONTEXT_PRE", "3"))
LOG_CONTEXT_POST = int(os.environ.get("LOG_CONTEXT_POST", "3"))
LOG_SCAN_INTERVAL = float(os.environ.get("LOG_SCAN_INTERVAL", "5"))

_pattern = re.compile(LOG_PATTERN, re.IGNORECASE)

_subscribers_lock = threading.Lock()
_subscribers = []

_event_seq_lock = threading.Lock()
_event_seq = 0

# Per-path last-seen inode. Lets us distinguish "first time we've ever
# seen this path" (seek to EOF; avoid re-reading accumulated history)
# from "this is a freshly-rotated file" (seek to BOF; capture everything
# written since rotation).
_inode_lock = threading.Lock()
_seen_inode: dict[str, int] = {}


def log(msg: str) -> None:
    sys.stderr.write(f"log-feed: {msg}\n")


def _broadcast(event: dict) -> None:
    line = (json.dumps(event) + "\n").encode()
    with _subscribers_lock:
        dead = []
        for entry in _subscribers:
            wfile, alive = entry
            try:
                wfile.write(f"{len(line):x}\r\n".encode())
                wfile.write(line)
                wfile.write(b"\r\n")
                wfile.flush()
            except Exception:
                alive[0] = False
                dead.append(entry)
        for entry in dead:
            _subscribers.remove(entry)


def _next_event_id() -> int:
    global _event_seq
    with _event_seq_lock:
        _event_seq += 1
        return _event_seq


# ---------------------------------------------------------------------------
# Per-file tailer thread
# ---------------------------------------------------------------------------

def _tail_file(path: str, platform: str, source: str) -> None:
    """
    Tail one log file. Exits when the file disappears or is rotated so
    the scanner can respawn a new tailer on the next scan tick.

    First time we've ever seen `path` → seek to EOF (don't re-read
    accumulated history since boot). Rotation (new inode on an already-
    known path) → seek to BOF (capture everything written to the fresh
    file, including lines produced in the rotation-to-rescan gap).
    """
    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except OSError as e:
        log(f"open failed {path}: {e}")
        return
    try:
        inode = os.fstat(fh.fileno()).st_ino
        with _inode_lock:
            prior = _seen_inode.get(path)
            _seen_inode[path] = inode
        if prior is None:
            fh.seek(0, os.SEEK_END)
            mode = "fresh:eof"
        elif prior != inode:
            # Rotation — new file on same path. Read from the start so we
            # don't lose the first lines written since rotation.
            mode = "rotated:bof"
        else:
            # Same inode: shouldn't really happen since we only get here
            # after a prior tailer exited, but handle it defensively.
            fh.seek(0, os.SEEK_END)
            mode = "resume:eof"
        log(f"tailing {path} ({mode} platform={platform} source={source} inode={inode})")

        pre_buf: deque[str] = deque(maxlen=LOG_CONTEXT_PRE)
        pending: list[dict] = []
        line_no = 0

        while True:
            line = fh.readline()
            if not line:
                # Detect rotation / deletion via inode change.
                try:
                    st = os.stat(path)
                    if st.st_ino != inode:
                        log(f"rotated: {path}")
                        return
                except FileNotFoundError:
                    log(f"gone: {path}")
                    return
                time.sleep(0.25)
                continue

            line_no += 1
            stripped = line.rstrip("\n")

            still = []
            for ev in pending:
                ev["post_context"].append(stripped)
                if len(ev["post_context"]) >= LOG_CONTEXT_POST:
                    _broadcast(ev)
                else:
                    still.append(ev)
            pending = still

            if _pattern.search(stripped):
                ev = {
                    "event_id": _next_event_id(),
                    "ts": time.time(),
                    "source_file": path,
                    "platform": platform,
                    "source": source,
                    "line_no": line_no,
                    "match": stripped,
                    "pre_context": list(pre_buf),
                    "post_context": [],
                }
                if LOG_CONTEXT_POST == 0:
                    _broadcast(ev)
                else:
                    pending.append(ev)

            pre_buf.append(stripped)
    finally:
        # Flush any events that were still collecting post-context when
        # the file rotated or disappeared. Their post_context may be
        # shorter than LOG_CONTEXT_POST, but dropping them silently is
        # worse than emitting partial context.
        try:
            if pending:
                for ev in pending:
                    ev["truncated"] = True
                    _broadcast(ev)
        except NameError:
            pass
        try:
            fh.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Directory scanner
# ---------------------------------------------------------------------------

def _scan_tree_and_spawn():
    """
    Walk LOG_ROOT = /pantavisor/logs/current/<platform>/<source> and
    spawn a tailer for any file we haven't already seen. Pantavisor's
    filetree output lays logs out as:

      <LOG_ROOT>/<container>/<source>          (plain log file)

    Subdirectories under <container> (e.g. 'lxc' for LXC console.log)
    are also handled — we recurse one extra level.
    """
    active: dict[str, threading.Thread] = {}

    def spawn_for(path: str):
        parts = os.path.relpath(path, LOG_ROOT).split(os.sep)
        platform = parts[0] if parts else "unknown"
        source = "/".join(parts[1:]) if len(parts) > 1 else os.path.basename(path)
        t = threading.Thread(
            target=_tail_file,
            args=(path, platform, source),
            daemon=True,
        )
        t.start()
        active[path] = t

    while True:
        if not os.path.isdir(LOG_ROOT):
            log(f"waiting for {LOG_ROOT} to appear")
        else:
            for root, _dirs, files in os.walk(LOG_ROOT):
                for fname in files:
                    # Skip compressed rotated files.
                    if fname.endswith(".gz") or fname.endswith(".xz"):
                        continue
                    path = os.path.join(root, fname)
                    t = active.get(path)
                    if t is None or not t.is_alive():
                        spawn_for(path)

        time.sleep(LOG_SCAN_INTERVAL)


def _single_file_mode_loop():
    """Fallback: tail one file forever, respawning on rotation."""
    while True:
        if not os.path.exists(LOG_SINGLE_PATH):
            time.sleep(LOG_SCAN_INTERVAL)
            continue
        _tail_file(LOG_SINGLE_PATH, "unknown", os.path.basename(LOG_SINGLE_PATH))


# ---------------------------------------------------------------------------
# Publish side
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def address_string(self):
        return "uds"

    def log_message(self, fmt, *args):
        sys.stderr.write("log-feed: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/info":
            body = json.dumps({
                "service": "log-feed",
                "mode": "single-file" if LOG_SINGLE_PATH else "filetree",
                "log_root": LOG_ROOT,
                "log_single_path": LOG_SINGLE_PATH,
                "pattern": LOG_PATTERN,
                "pre_context": LOG_CONTEXT_PRE,
                "post_context": LOG_CONTEXT_POST,
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if self.path == "/subscribe":
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson")
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            alive = [True]
            entry = (self.wfile, alive)
            with _subscribers_lock:
                _subscribers.append(entry)
            self.log_message("subscriber joined (total=%d)", len(_subscribers))
            while alive[0]:
                time.sleep(0.5)
            return

        self.send_response(404)
        self.end_headers()


class UnixHTTPServer(HTTPServer):
    def server_bind(self):
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()


class ThreadedUnixHTTPServer(UnixHTTPServer):
    daemon_threads = True

    def process_request(self, request, client_address):
        t = threading.Thread(
            target=self.process_request_thread, args=(request, client_address)
        )
        t.daemon = True
        t.start()

    def process_request_thread(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        finally:
            self.shutdown_request(request)


def run(socket_path: str):
    if os.path.exists(socket_path):
        os.remove(socket_path)
    os.makedirs(os.path.dirname(socket_path), exist_ok=True)

    httpd = ThreadedUnixHTTPServer(socket_path, Handler, bind_and_activate=False)
    httpd.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    httpd.server_bind()
    httpd.server_activate()

    if LOG_SINGLE_PATH:
        log(f"single-file mode: {LOG_SINGLE_PATH}")
        threading.Thread(target=_single_file_mode_loop, daemon=True).start()
    else:
        log(f"filetree mode: walking {LOG_ROOT}")
        threading.Thread(target=_scan_tree_and_spawn, daemon=True).start()

    log(f"publishing on {socket_path}")
    httpd.serve_forever()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/run/logs/feed.sock"
    run(path)
