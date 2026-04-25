#!/usr/bin/env python3
"""
Agentic camera-mock

Drop-in replacement for agentic-camera-feed that serves real JPEG/PNG
frames cycled from an on-disk directory (bundled at build time). Same
xconnect service name ("camera-feed"), same /subscribe NDJSON protocol —
so downstream (camera-analyzer, …) can consume it without changes.

Env overrides:
  IMAGES_DIR         path to bundled frames (default
                     /usr/share/agentic-camera-mock/images)
  FRAME_INTERVAL_S   seconds between frames (default 2.0)
"""

import base64
import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

IMAGES_DIR = os.environ.get("IMAGES_DIR", "/usr/share/agentic-camera-mock/images")
FRAME_INTERVAL_S = float(os.environ.get("FRAME_INTERVAL_S", "2.0"))

_subscribers_lock = threading.Lock()
_subscribers = []


def log(msg: str) -> None:
    sys.stderr.write(f"camera-mock: {msg}\n")


def _format_from_name(name: str) -> str:
    ext = os.path.splitext(name)[1].lower().lstrip(".")
    return {"jpg": "jpeg", "jpeg": "jpeg", "png": "png"}.get(ext, ext)


def _load_frames(directory: str) -> list[tuple[str, str, bytes]]:
    """Returns a list of (filename, format, bytes) tuples, sorted by name."""
    frames = []
    if not os.path.isdir(directory):
        return frames
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        fmt = _format_from_name(name)
        if fmt not in ("jpeg", "png"):
            continue
        try:
            with open(path, "rb") as f:
                frames.append((name, fmt, f.read()))
        except OSError as e:
            log(f"skip {path}: {e}")
    return frames


def producer_loop(frames: list[tuple[str, str, bytes]]):
    if not frames:
        log(f"FATAL: no frames in {IMAGES_DIR}")
        return
    log(f"loaded {len(frames)} frames from {IMAGES_DIR}")
    frame_id = 0
    while True:
        name, fmt, payload = frames[frame_id % len(frames)]
        msg = {
            "frame_id": frame_id,
            "ts": time.time(),
            "format": fmt,
            "source_name": name,
            "bytes": len(payload),
            "data": base64.b64encode(payload).decode("ascii"),
        }
        line = (json.dumps(msg) + "\n").encode()
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
        frame_id += 1
        time.sleep(FRAME_INTERVAL_S)


# ---------------------------------------------------------------------------
# Publish side
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    def address_string(self):
        return "uds"

    def log_message(self, fmt, *args):
        sys.stderr.write("camera-mock: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/info":
            body = json.dumps({
                "service": "camera-feed",
                "mode": "mock",
                "images_dir": IMAGES_DIR,
                "frame_rate_hz": 1.0 / FRAME_INTERVAL_S,
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

    frames = _load_frames(IMAGES_DIR)

    httpd = ThreadedUnixHTTPServer(socket_path, Handler, bind_and_activate=False)
    httpd.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    httpd.server_bind()
    httpd.server_activate()

    threading.Thread(target=producer_loop, args=(frames,), daemon=True).start()
    log(f"publishing on {socket_path}")
    httpd.serve_forever()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/run/camera/feed.sock"
    run(path)
