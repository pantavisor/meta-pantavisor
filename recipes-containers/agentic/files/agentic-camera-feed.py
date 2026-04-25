#!/usr/bin/env python3
"""
Agentic camera-feed

Publishes synthetic image frames to all subscribers over HTTP chunked
transfer on a Unix domain socket. Each message is one newline-terminated
JSON object (NDJSON) — websocket-style pub/sub without the framing overhead,
and consumable by any curl --unix-socket client.

Endpoints:
  GET /info            -> JSON describing the feed
  GET /subscribe       -> chunked stream of NDJSON frames (one per line)
"""

import base64
import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

FRAME_INTERVAL_S = 1.0
FRAME_WIDTH = 64
FRAME_HEIGHT = 48

_subscribers_lock = threading.Lock()
_subscribers = []  # list of (wfile, alive_flag_list)


def synthetic_frame(frame_id: int) -> bytes:
    """
    Produce a minimal PPM image payload. Real deployments would plug in
    v4l2 / gstreamer / libcamera here.
    """
    header = f"P6\n{FRAME_WIDTH} {FRAME_HEIGHT}\n255\n".encode()
    # Cheap moving gradient so consecutive frames differ.
    pixels = bytearray(FRAME_WIDTH * FRAME_HEIGHT * 3)
    shift = frame_id & 0xFF
    for y in range(FRAME_HEIGHT):
        for x in range(FRAME_WIDTH):
            i = (y * FRAME_WIDTH + x) * 3
            pixels[i] = (x + shift) & 0xFF
            pixels[i + 1] = (y + shift) & 0xFF
            pixels[i + 2] = (x + y) & 0xFF
    return header + bytes(pixels)


def producer_loop():
    frame_id = 0
    while True:
        payload = synthetic_frame(frame_id)
        msg = {
            "frame_id": frame_id,
            "ts": time.time(),
            "format": "ppm",
            "width": FRAME_WIDTH,
            "height": FRAME_HEIGHT,
            "data": base64.b64encode(payload).decode("ascii"),
        }
        line = (json.dumps(msg) + "\n").encode()
        with _subscribers_lock:
            dead = []
            for entry in _subscribers:
                wfile, alive = entry
                try:
                    chunk_len = f"{len(line):x}\r\n".encode()
                    wfile.write(chunk_len)
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


class Handler(BaseHTTPRequestHandler):
    def address_string(self):
        return "uds"

    def log_message(self, fmt, *args):
        sys.stderr.write("camera-feed: " + (fmt % args) + "\n")

    def do_GET(self):
        if self.path == "/info":
            body = json.dumps({
                "service": "camera-feed",
                "frame_format": "ppm",
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
            # Keep the handler alive until the producer flags us dead.
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
    # One thread per subscriber.
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

    threading.Thread(target=producer_loop, daemon=True).start()
    print(f"camera-feed listening on {socket_path}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "/run/camera/feed.sock"
    run(path)
